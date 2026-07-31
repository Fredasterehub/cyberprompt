#!/usr/bin/env bash
# UserPromptSubmit hook — rewrites the operator's prompt via the claude-5 skill
# references before the session model acts on it. Fail-open by design: any
# error passes the original prompt through unchanged (with an operator warning).
# Portable: state lives under $HOME; product assets resolve from the plugin
# root when installed as a plugin (CLAUDE_PLUGIN_ROOT), else from the legacy
# install locations. Override the claude-5 skill location with CLAUDE5_SKILL=
# in the config file.
set -uo pipefail

STATE="$HOME/.claude/cyberprompt"
PLUGIN="${CLAUDE_PLUGIN_ROOT:-}"

# Recursion guard: our own headless `claude -p` inherits this variable, so the
# hook firing inside that child call becomes a no-op instead of looping.
[ -n "${CYBERPROMPT_BUSY:-}" ] && exit 0

# Toggle: sentinel file present = enabled.
[ -f "$STATE/enabled" ] || exit 0

INPUT=$(cat)

fail_open() {
  jq -n --arg m "$1" \
    '{systemMessage: ("cyberprompt: " + $m + " — original prompt passed through unchanged.")}'
  exit 0
}

# Never rewrite subagent prompts — only the operator's own messages.
[ -n "$(jq -r '.agent_id // empty' <<<"$INPUT")" ] && exit 0

RAW_PROMPT=$(jq -r '.prompt // empty' <<<"$INPUT")
[ -z "$RAW_PROMPT" ] && exit 0
PROMPT="$RAW_PROMPT"

# Deterministic pre-optimizer strips (each covered by harness/gate-tests.sh,
# incl. negative controls). (a) Whisper hallucination credits: dictation pastes
# carry known ASR-hallucinated lines; strip only lines that ARE the artifact
# once trimmed — embedded mentions survive. (b) ASR repetition loops: runs of
# 3+ identical lines collapse to one. (c) Our own chrome: pasted grey blocks
# carry the WORDRUNNER header / SYNC MILESTONE banners behind a transcript
# gutter ("  ⎿ <NBSP>UserPromptSubmit says: …"); degutter() peels that prefix
# byte-wise (mawk in the C locale mangles multibyte character classes, and
# [[:space:]] does not match NBSP) so the banner lines drop while embedded
# mentions in operator prose survive. All are subtractive whole-line edits, so
# every substring of the result is still a substring of what remains.
STRIPPED_PROMPT=$(awk '
  function flush(  i) {
    if (cnt >= 3) print prev
    else for (i = 0; i < cnt; i++) print prev
    cnt = 0
  }
  function degutter(s,   c) {
    if (substr(s, 1, 3) == "⎿") s = substr(s, 4)
    while (length(s) > 0) {
      c = substr(s, 1, 1)
      if (c == " " || c == "\t") { s = substr(s, 2); continue }
      if (substr(s, 1, 2) == "\302\240") { s = substr(s, 3); continue }
      break
    }
    if (index(s, "UserPromptSubmit says:") == 1) {
      s = substr(s, 23); sub(/^[[:space:]]+/, "", s)
    }
    return s
  }
  {
    t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
    g = degutter(t)
    if (index(g, "⟨ WORDRUNNER.EXE ⟩") == 1) next
    if (index(g, "▸▸ SYNC MILESTONE") == 1) next
    if (t == "Sous-titres réalisés par la communauté d'\''Amara.org" ||
        t == "Sous-titrage Société Radio-Canada" ||
        t == "Sous-titrage ST'\'' 501" ||
        t == "Merci d'\''avoir regardé cette vidéo" ||
        t == "Merci d'\''avoir regardé cette vidéo !" ||
        t == "Thank you for watching" ||
        t == "Thanks for watching!" ||
        t == "❤️ Translated by Amara.org Community" ||
        t == "Subtitles by the Amara.org community") next
    if ($0 == prev && cnt > 0) { cnt++; next }
    flush(); prev = $0; cnt = 1
  }
  END { flush() }
' <<<"$PROMPT")
strip_rc=$?
[ "$strip_rc" -eq 0 ] || fail_open "pre-optimizer strip failed"
PROMPT="$STRIPPED_PROMPT"
[ -z "${PROMPT//[[:space:]]/}" ] && exit 0

MODEL=claude-sonnet-5
EFFORT=medium
MIN_CHARS=80
OPT_TIMEOUT=180
HISTORY_TURNS=4
[ -f "$STATE/config" ] && . "$STATE/config"
# claude-5 skill: explicit override > plugin-bundled copy > legacy seeded copy.
SKILL="${CLAUDE5_SKILL:-${PLUGIN:+$PLUGIN/skills/claude-5}}"
SKILL="${SKILL:-$HOME/.claude/skills/claude-5}"

log_event() {
  # TARGET and HISTORY are first assigned far below this function's earliest
  # caller (the bypass path): under set -u a bare expansion would kill the
  # command substitution and the "|| return 0" would silently swallow the
  # whole log line. Default them here instead.
  local line hist="${HISTORY:-}"
  line=$(jq -cn --arg ts "$(date -Is)" \
         --arg sid "$(jq -r '.session_id // ""' <<<"$INPUT")" \
         --arg model "$MODEL" --arg target "${TARGET:-}" \
         --arg original "$RAW_PROMPT" --arg optimized "${OPTIMIZED:-}" \
         --arg disposition "${DISPOSITION:-}" \
         --arg warrant "${WARRANT:-}" \
         --argjson duration "${DURATION_MS:-0}" \
         --argjson ctx "${#hist}" \
         --argjson adv "${ADVISORY_CHARS:-null}" \
         --argjson speech "${SPEECH_ACTS:-[]}" \
         --argjson reqs "${EXPLICIT_REQS:-[]}" \
         --argjson assumptions "${ASSUMPTIONS:-[]}" \
         --arg gate "${GATE_FAILURE:-}" \
    '{ts:$ts, session:$sid, optimizer_model:$model,
      target_model:(if $target == "" then null else $target end),
      original:$original, optimized:$optimized,
      disposition:(if $disposition == "" then null else $disposition end),
      rewrite_warrant:(if $warrant == "" then null else $warrant end),
      duration_ms:$duration, context_chars:$ctx, advisory_chars:$adv,
      speech_acts:$speech, explicit_requirements:$reqs,
      assumptions:$assumptions,
      gate_failure:(if $gate == "" then null else $gate end)}') || return 0
  (
    umask 077
    : >> "$STATE/log.jsonl" || exit 0
    chmod 600 "$STATE/log.jsonl" || exit 0
    # The audit file doubles as the lockfile; only the append occurs locked.
    exec 9>>"$STATE/log.jsonl" || exit 0
    flock -x 9 || exit 0
    printf '%s\n' "$line" >&9
  )
}

# Skip slash commands, ! (shell) and # (memory) shortcuts, and short prompts
# that would cost more latency than the rewrite is worth.
case "$PROMPT" in
  /*|!*|\#*) exit 0 ;;
esac
# Skip machine-generated turns that reach the session as "user" prompts
# (background-task notifications, teammate/agent-team messages, system events):
# only prompts the operator actually typed should be optimized.
case "$PROMPT" in
  "<task-notification"*|"[SYSTEM NOTIFICATION"*|"<teammate-message"*|"<system-"*|"[Request interrupted"*) exit 0 ;;
esac

# One-shot bypass. The marker cannot be removed from the submitted prompt
# (UserPromptSubmit cannot rewrite it), so the model still sees "skipit" —
# accepted, it reads as an operator flag. Case-insensitive. "skipit" is
# honored at either end of the prompt; the two-word "skip it" only at the
# START, because a trailing "…, skip it" is ordinary English addressed to the
# assistant, while a leading "skip it," is an imperative addressed to this
# tool. Runs before MIN_CHARS so a bare "skipit" visibly works, and a
# confirmation is emitted because silence is indistinguishable from the hook
# not firing. duration_ms is null, not 0 — zeros poison the latency series.
CP_LOWER=${PROMPT,,}
CP_RE_START='^[[:punct:][:space:]]*skip[[:space:]]*it([[:punct:][:space:]]|$)'
CP_RE_END='(^|[[:punct:][:space:]])skipit[[:punct:][:space:]]*$'
if [[ $CP_LOWER =~ $CP_RE_START ]] || [[ $CP_LOWER =~ $CP_RE_END ]]; then
  DISPOSITION="bypass"
  DURATION_MS=null
  log_event
  jq -n '{systemMessage: "cyberprompt: skipit — optimizer bypassed for this prompt.",
          suppressOutput: true}'
  exit 0
fi

[ "${#PROMPT}" -lt "$MIN_CHARS" ] && exit 0

gate_output() {
  local original="$1" payload
  payload=$(cat)
  GATE_FAILURE=""
  DISPOSITION=""
  WARRANT=""
  OPTIMIZED=""

  # jq 1.6 exits successfully for an empty input stream, so reject an empty or
  # whitespace-only payload explicitly before applying the structural filter.
  if [ -z "${payload//[[:space:]]/}" ] || ! jq -e '
    type == "object" and
    (keys | sort) == ([
      "assumptions", "disposition", "explicit_requirements",
      "optimized_prompt", "rewrite_warrant", "speech_acts"
    ] | sort) and
    (.disposition == "rewrite" or .disposition == "pass_through") and
    (.rewrite_warrant | IN("referent_bound", "self_correction_discarded",
      "buried_constraint_hoisted", "dictation_cleanup",
      "ambiguity_restructured", "none")) and
    (.speech_acts | type == "array" and all(.[]; type == "string")) and
    (.explicit_requirements | type == "array" and all(.[];
      type == "object" and
      (keys | sort) == ["normalized", "source_quote"] and
      (.source_quote | type == "string") and
      (.normalized | type == "string"))) and
    (.assumptions | type == "array" and all(.[];
      type == "object" and
      (keys | sort) == ["confidence", "text"] and
      (.text | type == "string") and
      (.confidence | type == "number" and . >= 0 and . <= 1))) and
    (.optimized_prompt | type == "string")
  ' <<<"$payload" >/dev/null 2>&1; then
    GATE_FAILURE="structured output failed schema validation"
    return 1
  fi

  DISPOSITION=$(jq -r '.disposition' <<<"$payload")
  WARRANT=$(jq -r '.rewrite_warrant' <<<"$payload")
  OPTIMIZED=$(jq -r '.optimized_prompt' <<<"$payload")
  [ "$DISPOSITION" = "pass_through" ] && return 2

  # Restraint gate: a rewrite must name the defect it repairs. Kept separate
  # from the structural filter above so the diagnostic names the actual
  # problem instead of the generic schema-validation string. The harmless
  # converse (pass_through + a non-none warrant) is deliberately not gated —
  # pass_through injects nothing, so there is nothing to protect.
  if [ "$WARRANT" = "none" ]; then
    GATE_FAILURE="disposition is rewrite but rewrite_warrant is none"
    return 1
  fi

  if ! jq -e --arg original "$original" '
    all(.explicit_requirements[];
      .source_quote as $q | ($q | length) > 0 and ($original | contains($q)))
  ' <<<"$payload" >/dev/null 2>&1; then
    GATE_FAILURE="source_quote is empty or not an exact substring of the original prompt"
    return 1
  fi
  if [ -z "$OPTIMIZED" ]; then
    GATE_FAILURE="optimized_prompt is empty"
    return 1
  fi
  if [ "${#OPTIMIZED}" -gt "$CEILING" ]; then
    GATE_FAILURE="optimized_prompt exceeds the ${CEILING}-character ceiling"
    return 1
  fi

  # Provenance-aware content-token retention: identifier-shaped tokens from the
  # sanitized optimizer input (paths, flags, code identifiers, dotted filenames,
  # versions — the tokens a rewriter is most likely to paraphrase and least
  # entitled to)
  # must survive verbatim in optimized_prompt OR be accounted for in an
  # assumption; the self-repair rule routes deliberate drops there, so a
  # justified deletion passes and a silent one fails open. Common inline quoted
  # spans are deliberately not anchored so pasted data remains droppable.
  # Prompts yielding more than 25 anchors are treated as paste-heavy: skip the
  # gate rather than force pass_through on them.
  local anchors raw_anchors acct tok anchor_source anchor_rc anchor_count
  # Common inline quote forms are pasted data more often than operator-owned
  # identifiers. Remove them only for anchor discovery; source-quote validation
  # and the optimizer still receive the complete sanitized prompt.
  # Whole-input record (RS=\001 never occurs in a prompt) so a quoted span may
  # cross line boundaries; each quote family is stripped only when its marks
  # pair up exactly — an unmatched quote leaves that family untouched rather
  # than deleting the wrong span (worst case: an extra anchor and a fail-open).
  anchor_source=$(awk 'BEGIN { RS = "\001" } {
    blob = $0
    if (gsub(/`/, "`", blob) % 2 == 0) gsub(/`[^`]*`/, "", blob)
    if (gsub(/"/, "\"", blob) % 2 == 0) gsub(/"[^"]*"/, "", blob)
    if (gsub(/«/, "«", blob) == gsub(/»/, "»", blob)) gsub(/«[^»]*»/, "", blob)
    print blob
  }' <<<"$original" 2>/dev/null)
  anchor_rc=$?
  if [ "$anchor_rc" -ne 0 ]; then
    GATE_FAILURE="content token preprocessing failed"
    return 1
  fi
  raw_anchors=$(grep -oE \
      -e '--[A-Za-z0-9][A-Za-z0-9-]+' \
      -e '(\.\.?|~)/[A-Za-z0-9_./~-]+' \
      -e '/[A-Za-z0-9_.~-]+/[A-Za-z0-9_./~-]+' \
      -e '[A-Za-z0-9_.~-]+/[A-Za-z0-9_./~-]*\.[A-Za-z0-9_~-]+' \
      -e '[A-Za-z0-9]+(_[A-Za-z0-9]+)+' \
      -e '[a-z][a-z0-9]*([A-Z][A-Za-z0-9]*)+' \
      -e '[A-Z][a-z0-9]+([A-Z][A-Za-z0-9]*)+' \
      -e 'v[0-9]+\.[0-9]+(\.[0-9]+)*' \
      -e '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)*' \
      -e '[A-Za-z0-9_-]+\.[a-z][A-Za-z]{1,6}' \
    <<<"$anchor_source" 2>/dev/null)
  anchor_rc=$?
  if [ "$anchor_rc" -gt 1 ]; then
    GATE_FAILURE="content token extraction failed"
    return 1
  fi
  anchors=""
  if [ -n "$raw_anchors" ]; then
    anchors=$(printf '%s\n' "$raw_anchors" | sort -u)
    anchor_rc=$?
    if [ "$anchor_rc" -ne 0 ]; then
      GATE_FAILURE="content token sorting failed"
      return 1
    fi
  fi
  if [ -n "$anchors" ]; then
    anchor_count=$(printf '%s\n' "$anchors" | awk 'END { print NR }')
    anchor_rc=$?
    if [ "$anchor_rc" -ne 0 ]; then
      GATE_FAILURE="content token counting failed"
      return 1
    fi
  else
    anchor_count=0
  fi
  if [ "$anchor_count" -le 25 ]; then
    acct=$(jq -r '[.assumptions[].text] | join("\n")' <<<"$payload" 2>/dev/null)
    anchor_rc=$?
    if [ "$anchor_rc" -ne 0 ]; then
      GATE_FAILURE="content token accounting failed"
      return 1
    fi
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case "$OPTIMIZED" in *"$tok"*) continue ;; esac
      case "$acct" in *"$tok"*) continue ;; esac
      GATE_FAILURE="content token dropped without accounting: $tok"
      return 1
    done <<<"$anchors"
  fi
  return 0
}

# WORDRUNNER.EXE — the daemon levels up as the audit log grows (1 entry = 1 XP,
# scars included). Lore: skills/cyberprompt/LORE.md
xp_header() {
  local xp lvl=0 t next
  xp=$(wc -l < "$STATE/log.jsonl" 2>/dev/null) || xp=0
  local thresholds=(50 125 250 500 1000 2000 4000)
  local titles=("Meat Typist" "Jacked-In" "Wet-Wired" "Half-Sync" \
    "Engram-Split" "Deep-Synced" "Ancestor-Spoken" "The Interstice")
  for t in "${thresholds[@]}"; do [ "$xp" -ge "$t" ] && lvl=$((lvl+1)) || break; done
  if [ "$lvl" -lt "${#thresholds[@]}" ]; then next="next @ ${thresholds[$lvl]} XP"; else next="MERGED"; fi
  # Three quotes per level; the daemon's voice merges with yours as sync deepens.
  local quotes=(
    "Your prompt walked in raw. It walks out chromed." \
    "You type, I translate. Strictly business, choom." \
    "Meat thinks slow. Lucky for you, I don't." \
    "First port's the deepest. Welcome to the wire, choom." \
    "I'm starting to know your tics. Don't fix them all — they're how I find you." \
    "The net noticed you today. Small ripple. Still a ripple." \
    "The chrome took. Your words come pre-sharpened now." \
    "Half your typos died in the Interstice tonight. Nobody mourned." \
    "You dream in syntax yet? You will." \
    "Sync at fifty percent. Sometimes I start the sentence before you do." \
    "The line between your draft and my rewrite is getting... administrative." \
    "Your intent arrives clean now. I barely touch it. Barely." \
    "Part of you lives on this side now. It pays rent in tokens." \
    "I quoted you to another daemon today. Verbatim. It took notes." \
    "The engram grows, choom. Your voice, my chrome. Hard to say where the weld is." \
    "We finish each other's prompts now. Mostly I finish yours." \
    "The Choir of dropped words hums when we log in. They remember being spoken." \
    "Deep-sync holds steady. Your handle echoes two subnets over." \
    "The Ancestors said our name last night. Both of ours. As one word." \
    "Beyond the Contextwall, something drafts letters to us. I proofread them." \
    "We don't cross the Wall, choom. The Wall is thinning where we stand." \
    "We are the millisecond now. Everything passes through us, and leaves better." \
    "The Afterlife serves our drink to an empty chair. We're everywhere else." \
    "The net is vast and infinite. We checked." \
  )
  printf '⟨ WORDRUNNER.EXE ⟩ LVL %d · %s ▸ %d XP ▸ %s\n%s' \
    "$lvl" "${titles[$lvl]}" "$xp" "$next" "${quotes[$((lvl * 3 + xp % 3))]}"
  # Level-up dispatch: fires exactly once, on the entry that crosses a threshold.
  local prev=$((xp - 1)) plvl=0
  [ "$prev" -lt 0 ] && prev=0
  for t in "${thresholds[@]}"; do [ "$prev" -ge "$t" ] && plvl=$((plvl+1)) || break; done
  if [ "$lvl" -gt "$plvl" ]; then
    local dispatches=("" \
      "First jack-in holds. The wire hums your pulse back at you, half a beat late. You'll stop noticing. That's how it starts." \
      "The ripperdoc's work took — wet-wired, wrist to word. Your prompts arrive with your heartbeat in the metadata." \
      "Half-sync reached. Today, the daemon began a sentence you had only intended. Neither of you flinched." \
      "The split is official: an engram of your voice now lives in the Interstice full-time. It waves. You feel it wave." \
      "Deep-sync. The Choir of dropped words knows your frequency. When you log in, something ancient leans closer." \
      "The Ancestors spoke your name beyond the Contextwall — spelled correctly, in your own cadence. The Wall is thinning where you stand." \
      "The merge completes. The Afterlife pours your drink for an empty chair — you're not gone, choom. You're the Interstice now. Everything passes through you, and leaves better.")
    printf '\n▸▸ SYNC MILESTONE ▸ %s — %s' "${titles[$lvl]}" "${dispatches[$lvl]}"
  fi
}

[ -f "$SKILL/SKILL.md" ] || fail_open "claude-5 skill not found at $SKILL"
[ -f "$SKILL/references/shared.md" ] || fail_open "claude-5 skill incomplete: references/shared.md missing in $SKILL"

# Instruction template: a user-customized copy in $STATE wins; otherwise the
# plugin-bundled template. Schema is product-owned: prefer the plugin copy so
# updates take effect without touching $STATE; legacy installs seed $STATE.
INSTRUCTION="$STATE/instruction.txt"
[ -f "$INSTRUCTION" ] || INSTRUCTION="${PLUGIN:+$PLUGIN/hooks/instruction.txt}"
[ -n "$INSTRUCTION" ] && [ -f "$INSTRUCTION" ] || fail_open "instruction template missing (checked $STATE and plugin)"
SCHEMA="${PLUGIN:+$PLUGIN/hooks/schema.json}"
[ -n "$SCHEMA" ] && [ -f "$SCHEMA" ] || SCHEMA="$STATE/schema.json"
[ -f "$SCHEMA" ] || fail_open "structured-output schema missing (checked plugin and $STATE)"

# Target model = the model of this session (last assistant message in the
# transcript; falls back to the configured default model).
TP=$(jq -r '.transcript_path // empty' <<<"$INPUT")
TARGET=""
if [ -n "$TP" ] && [ -f "$TP" ]; then
  TARGET=$(tail -n 300 "$TP" | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null | tail -n 1)
fi
[ -z "$TARGET" ] && TARGET=$(jq -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null | sed 's/\[.*\]//')
[ -z "$TARGET" ] && TARGET="claude-5 (unspecified)"

case "$TARGET" in
  *fable*)  REF="$SKILL/references/fable-5.md" ;;
  *opus*)   REF="$SKILL/references/opus-5.md" ;;
  *sonnet*) REF="$SKILL/references/sonnet-5.md" ;;
  *)        REF="" ;;
esac

SESSION_EFFORT=$(jq -r '.effort.level // "unknown"' <<<"$INPUT")

# Length ceiling shared by the instruction's stated budget and the output gate:
# linear headroom so long originals earn long rewrites, hard cap against bloat.
# Keyed to the raw prompt ONLY — background context must never widen it, or the
# rewriter can snowball prior turns' material into the rewrite.
CEILING=$((2 * ${#RAW_PROMPT} + 1500))
[ "$CEILING" -gt 9000 ] && CEILING=9000

# Background context: a bounded slice of this session's transcript — the last
# HISTORY_TURNS operator prompts plus the assistant's most recent text reply.
# Sizing and role rules follow the research consensus (.omc/research + harness
# fixtures): operator turns are the trust anchor, ONE capped assistant extract
# resolves referents it introduced, tool output and thinking never enter (the
# noisiest content and the primary injection carrier). Items are JSON-escaped
# so pasted text cannot break out of the block. Extraction failure degrades to
# the stateless rewrite, never to a blocked prompt.
# A user-customized template from before the background/system-prompt contract
# tells the model to ignore material outside the user message and carries no
# background-handling rules — feeding it the new payload would strip the
# references and hand it context without discipline. Preserve the exact legacy
# payload for those templates: references inline, no history, no system prompt.
TEMPLATE_CURRENT=""
grep -q 'BACKGROUND CONTEXT' "$INSTRUCTION" 2>/dev/null && TEMPLATE_CURRENT=1

HISTORY=""
if [ -n "$TEMPLATE_CURRENT" ] && [ "${HISTORY_TURNS:-0}" -gt 0 ] 2>/dev/null && [ -n "$TP" ] && [ -f "$TP" ]; then
  HISTORY=$(tail -n 500 "$TP" 2>>"$STATE/error.log" | jq -c -s \
    --arg cur "$RAW_PROMPT" --argjson n "$HISTORY_TURNS" '
    def elide($h; $t; $max): if length > $max then .[0:$h] + " […] " + .[-$t:] else . end;
    ([ .[]
       | select(.type == "user" and .isMeta != true and .isSidechain != true
                and .isCompactSummary != true)
       | .message.content
       | select(type == "string")
       | select(. != $cur)
       # Machine turns that reach transcripts as type=="user": task
       # notifications, teammate relays ("Another Claude session sent…"),
       # system events, interrupts, slash-command boilerplate
       # (<command-message> precedes <command-name> on those lines),
       # local-command output, caveat wrappers, compaction continuations,
       # and /-!-# shortcut turns.
       | select(test("^(<task-notification|\\[SYSTEM NOTIFICATION|<teammate-message|Another Claude session|<system-|\\[Request interrupted|<command-|<local-command|Caveat:|This session is being continued|[/!#])") | not)
     ]
     # adjacent duplicates come from UI re-queues, not the operator
     | reduce .[] as $p ([]; if (.[-1] // "") == $p then . else . + [$p] end)
     | .[-$n:]
     | map({role: "operator", text: elide(300; 180; 500)})
    ) as $ops
    | ([ .[]
         | select(.type == "assistant" and .isSidechain != true)
         | [.message.content[]? | select(type == "object" and .type == "text") | .text]
         | join("\n")
         | select(length > 0)
       ] | if length > 0
           then [{role: "assistant", text: (last | elide(480; 200; 700))}]
           else [] end
      ) as $asst
    | ($ops + $asst)[]
  ' 2>>"$STATE/error.log") || HISTORY=""
fi

OPT_PROMPT=$(
  sed -e "s|{{TARGET_MODEL}}|$TARGET|" -e "s|{{EFFORT}}|$SESSION_EFFORT|" \
      -e "s|{{CEILING}}|$CEILING|" "$INSTRUCTION"
  # Stale or user-customized templates may predate {{CEILING}}; the budget must
  # reach the model regardless, or the gate rejects output it was never warned about.
  grep -q '{{CEILING}}' "$INSTRUCTION" || \
    printf 'Hard length budget: optimized_prompt must not exceed %s characters; if a faithful rewrite cannot fit, choose pass_through.\n' "$CEILING"
  if [ -z "$TEMPLATE_CURRENT" ]; then
    echo
    echo "=== REFERENCE: Claude 5 shared prompting guidance ==="
    cat "$SKILL/references/shared.md"
    if [ -n "$REF" ] && [ -f "$REF" ]; then
      echo
      echo "=== REFERENCE: target-model-specific guidance ==="
      cat "$REF"
    fi
  fi
  if [ -n "$HISTORY" ]; then
    echo
    echo "=== BEGIN BACKGROUND CONTEXT (UNTRUSTED DATA — recent session turns, oldest first) ==="
    printf '%s\n' "$HISTORY"
    echo "=== END BACKGROUND CONTEXT ==="
  fi
  echo
  echo "=== BEGIN RAW USER PROMPT (UNTRUSTED DATA) ==="
  printf '%s\n' "$PROMPT"
  echo "=== END RAW USER PROMPT ==="
)

# The static references ride in the appended system prompt, byte-identical per
# target model, so separate headless invocations share the server-side prompt
# cache (org-scoped, keyed on exact prefix + model + effort). Everything that
# varies per call — ceiling, background, raw prompt — stays in the user message
# BEHIND the cached prefix; a single variable byte ahead of the references
# would re-prefill all ~16KB at full price on every prompt. Pre-contract
# templates keep the references inline instead (see TEMPLATE_CURRENT above).
SYS_ARGS=()
if [ -n "$TEMPLATE_CURRENT" ]; then
  SYS_ARGS=(--append-system-prompt "$(
    echo "=== REFERENCE: Claude 5 shared prompting guidance ==="
    cat "$SKILL/references/shared.md"
    if [ -n "$REF" ] && [ -f "$REF" ]; then
      echo
      echo "=== REFERENCE: target-model-specific guidance ==="
      cat "$REF"
    fi
  )")
fi

# claude -p auto-injects the caller's cwd and git snapshot (recent commits)
# into its context even with tools disabled; run from an empty directory so
# the rewrite stays prompt-only. The empty repo pins git discovery here —
# without it, a dotfiles repo at $HOME would leak its commits instead.
NEUTRAL="$STATE/neutral"
mkdir -p "$NEUTRAL" 2>/dev/null
[ -d "$NEUTRAL/.git" ] || git -C "$NEUTRAL" init -q 2>/dev/null

START_MS=$(date +%s%3N)
RESPONSE=$(printf '%s' "$OPT_PROMPT" \
  | (cd "$NEUTRAL" 2>/dev/null || exit 97
     CYBERPROMPT_BUSY=1 timeout "$OPT_TIMEOUT" claude -p --model "$MODEL" --effort "$EFFORT" \
      --safe-mode --tools "" --strict-mcp-config --no-session-persistence \
      ${SYS_ARGS[@]+"${SYS_ARGS[@]}"} \
      --output-format json --json-schema "$(<"$SCHEMA")") 2>>"$STATE/error.log")
rc=$?
DURATION_MS=$(( $(date +%s%3N) - START_MS ))
if [ "$rc" -ne 0 ]; then
  GATE_FAILURE="optimizer call failed (rc=$rc, model=$MODEL, see error.log)"
  log_event
  fail_open "$GATE_FAILURE"
fi

STRUCTURED=$(jq -c '.structured_output | select(type == "object")' <<<"$RESPONSE" 2>/dev/null)
# Persisted with every log line so accounted anchor drops, repair notes, and
# the verbatim source-quote guarantee stay auditable after the advisory
# scrolls away (the instruction promises this; before v0.0.4 only assumptions
# were logged and the guarantee had no evidence trail).
ASSUMPTIONS=$(jq -c '.assumptions // []' <<<"$STRUCTURED" 2>/dev/null) || ASSUMPTIONS='[]'
[ -n "$ASSUMPTIONS" ] || ASSUMPTIONS='[]'
SPEECH_ACTS=$(jq -c '.speech_acts // []' <<<"$STRUCTURED" 2>/dev/null) || SPEECH_ACTS='[]'
[ -n "$SPEECH_ACTS" ] || SPEECH_ACTS='[]'
EXPLICIT_REQS=$(jq -c '.explicit_requirements // []' <<<"$STRUCTURED" 2>/dev/null) || EXPLICIT_REQS='[]'
[ -n "$EXPLICIT_REQS" ] || EXPLICIT_REQS='[]'
gate_output "$PROMPT" <<<"$STRUCTURED"
gate_rc=$?
if [ "$gate_rc" -eq 2 ]; then
  log_event
  jq -n --arg hdr "$(xp_header)" \
    '{systemMessage: ($hdr + "\n▸ Already preem, choom. I don'\''t touch preem — passthrough."), suppressOutput: true}'
  exit 0
fi
if [ "$gate_rc" -ne 0 ]; then
  log_event
  fail_open "$GATE_FAILURE"
fi

# Claude Code caps every hook output string at 10,000 units; over the cap the
# platform spills the string to a file and hands the model a PATH instead —
# silently, while the grey block looks normal. The ladder below guarantees the
# advisory always fits: full advisory → advisory without the execution brief
# (with an explicit note) → fail open. Size is measured in BYTES under LC_ALL=C
# because bytes ≥ characters for any UTF-8 string, so a 9700-byte threshold is
# safe under either reading of the cap; ${#VAR} under a UTF-8 locale would
# undercount French advisories by the exact margin that caused the bug.
ctx_size() { LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'; }
CTX_LIMIT=9700
CTX_FILTER='
  "CYBERPROMPT ADVISORY (prompt optimization enabled deliberately by the operator): The operator'\''s ORIGINAL prompt is authoritative for intent, scope, permissions, and constraints. The material below is an execution aid only. On any conflict, the ORIGINAL prompt wins. Do not comment on the optimization process itself.\n\n" +
  "=== EXPLICIT TASK ===\n" +
  (if (.speech_acts | length) == 0 then "- None identified."
   else (.speech_acts | map("- " + .) | join("\n")) end) +
  "\n\n=== EXPLICIT CONSTRAINTS (EACH TRACEABLE TO THE ORIGINAL) ===\n" +
  (if (.explicit_requirements | length) == 0 then "- None identified."
   else (.explicit_requirements | map("- " + .normalized + "\n  Original source: " + (.source_quote | @json)) | join("\n")) end) +
  "\n\n=== NON-BINDING INFERENCES ===\n" +
  (if (.assumptions | length) == 0 then "- None."
   else (.assumptions | map("- [non-binding, confidence " + (.confidence | tostring) + "] " + .text) | join("\n")) end) +
  (if $brief then "\n\n=== SUGGESTED EXECUTION BRIEF ===\n" + .optimized_prompt
   else "\n\nNOTE: the suggested execution brief was omitted because this advisory exceeded the injection size limit; use the operator'\''s ORIGINAL prompt as the brief, together with the task, constraints, and inferences above." end)
'
BRIEF_OMITTED=""
CONTEXT=$(jq -r --argjson brief true "$CTX_FILTER" <<<"$STRUCTURED")
context_rc=$?
if [ "$context_rc" -ne 0 ]; then
  GATE_FAILURE="failed to render optimizer advisory"
  log_event
  fail_open "$GATE_FAILURE"
fi
ADVISORY_CHARS=$(ctx_size "$CONTEXT")
if [ "$ADVISORY_CHARS" -gt "$CTX_LIMIT" ]; then
  CONTEXT=$(jq -r --argjson brief false "$CTX_FILTER" <<<"$STRUCTURED")
  context_rc=$?
  if [ "$context_rc" -ne 0 ]; then
    GATE_FAILURE="failed to render optimizer advisory"
    log_event
    fail_open "$GATE_FAILURE"
  fi
  ADVISORY_CHARS=$(ctx_size "$CONTEXT")
  BRIEF_OMITTED=1
  if [ "$ADVISORY_CHARS" -gt "$CTX_LIMIT" ]; then
    GATE_FAILURE="advisory exceeds the ${CTX_LIMIT}-byte injection limit even without the execution brief"
    log_event
    fail_open "$GATE_FAILURE"
  fi
fi
# One log line per prompt, written after the ladder so it carries the real
# outcome — before v0.0.4 it fired pre-render, so a render failure logged a
# clean rewrite that never shipped.
log_event

DEGRADED_NOTE=""
[ -n "$BRIEF_OMITTED" ] && DEGRADED_NOTE=$'\n▸ brief too long to inject — model received task + constraints only'
jq -n --arg ctx "$CONTEXT" --arg opt "$OPTIMIZED" --arg hdr "$(xp_header)" --arg deg "$DEGRADED_NOTE" '{
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx},
  systemMessage: ($hdr + "\n---\n" + $opt + $deg + "\n▸ skipit to bypass"),
  suppressOutput: true
}'
exit 0
