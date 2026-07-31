#!/usr/bin/env bash
# Codex UserPromptSubmit hook. The original prompt always continues; only a
# validated advisory may be added. Every failure is fail-open.
set -uo pipefail

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
STATE="$CODEX_ROOT/cyberprompt"
PLUGIN="${PLUGIN_ROOT:-}"
if [ -z "$PLUGIN" ]; then
  PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)
fi

# The nested `codex exec` inherits this guard. If plugin hooks are visible to
# the child despite --ignore-user-config, its UserPromptSubmit hook is a no-op.
[ -n "${CYBERPROMPT_BUSY:-}" ] && exit 0

# Instant, update-stable toggle. Installing the plugin does not opt the user in.
[ -f "$STATE/enabled" ] || exit 0

INPUT=$(cat)

if ! jq --version >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"cyberprompt: jq executable not found — original prompt passed through unchanged."}'
  exit 0
fi

fail_open() {
  jq -n --arg m "$1" \
    '{systemMessage: ("cyberprompt: " + $m + " — original prompt passed through unchanged.")}'
  exit 0
}

# Current Codex schemas expose agent_id on subagent turns. Never optimize an
# agent-to-agent instruction; CyberPrompt is for the operator's own prompt.
[ -n "$(jq -r '.agent_id // empty' <<<"$INPUT" 2>/dev/null)" ] && exit 0

RAW_PROMPT=$(jq -r '.prompt // empty' <<<"$INPUT" 2>/dev/null)
[ -n "$RAW_PROMPT" ] || exit 0
PROMPT="$RAW_PROMPT"

# Clean only the optimizer's private copy. Whole-line credit hallucinations,
# 3+ identical-line ASR loops, and pasted WORDRUNNER chrome are subtractive;
# the submitted user message itself is never replaced.
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
    if (index(s, "hook context:") == 1) {
      s = substr(s, 14); sub(/^[[:space:]]+/, "", s)
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
[ -n "${PROMPT//[[:space:]]/}" ] || exit 0

MODEL=gpt-5.6-sol
EFFORT=low
MIN_CHARS=80
OPT_TIMEOUT=180
HISTORY_TURNS=4

# Parse the small config as data. Unlike the legacy Claude hook, never source a
# config file as executable shell.
if [ -f "$STATE/config" ]; then
  while IFS='=' read -r config_key config_value; do
    config_key=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$config_key")
    config_value=$(sed 's/[[:space:]]*#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$config_value")
    case "$config_key" in
      MODEL) MODEL="$config_value" ;;
      EFFORT) EFFORT="$config_value" ;;
      MIN_CHARS) MIN_CHARS="$config_value" ;;
      OPT_TIMEOUT) OPT_TIMEOUT="$config_value" ;;
      HISTORY_TURNS) HISTORY_TURNS="$config_value" ;;
      ""|\#*) ;;
    esac
  done < "$STATE/config"
fi

case "$MODEL" in gpt-5.6-sol) ;; *) fail_open "unsupported optimizer MODEL=$MODEL" ;; esac
case "$EFFORT" in low|medium|high|xhigh|max|ultra) ;; *) fail_open "unsupported optimizer EFFORT=$EFFORT" ;; esac
case "$MIN_CHARS:$OPT_TIMEOUT:$HISTORY_TURNS" in
  *[!0-9:]*|:*|*::*|*:) fail_open "numeric config values are invalid" ;;
esac
[ "$OPT_TIMEOUT" -gt 0 ] 2>/dev/null || fail_open "OPT_TIMEOUT must be positive"

umask 077
mkdir -p "$STATE" 2>/dev/null || fail_open "cannot create state directory"
chmod 700 "$STATE" 2>/dev/null || fail_open "cannot secure state directory"

TARGET=$(jq -r '.model // empty' <<<"$INPUT" 2>/dev/null)

log_event() {
  local line hist="${HISTORY:-}"
  line=$(jq -cn --arg ts "$(date -Is)" \
         --arg sid "$(jq -r '.session_id // ""' <<<"$INPUT" 2>/dev/null)" \
         --arg turn "$(jq -r '.turn_id // ""' <<<"$INPUT" 2>/dev/null)" \
         --arg model "$MODEL" --arg effort "$EFFORT" --arg target "${TARGET:-}" \
         --arg original "$RAW_PROMPT" --arg optimized "${OPTIMIZED:-}" \
         --arg disposition "${DISPOSITION:-}" --arg warrant "${WARRANT:-}" \
         --argjson duration "${DURATION_MS:-null}" \
         --argjson ctx "${#hist}" --argjson adv "${ADVISORY_CHARS:-null}" \
         --argjson speech "${SPEECH_ACTS:-[]}" \
         --argjson reqs "${EXPLICIT_REQS:-[]}" \
         --argjson assumptions "${ASSUMPTIONS:-[]}" \
         --arg gate "${GATE_FAILURE:-}" \
    '{ts:$ts, session:$sid, turn:$turn, optimizer_model:$model,
      optimizer_effort:$effort,
      target_model:(if $target == "" then null else $target end),
      original:$original, optimized:$optimized,
      disposition:(if $disposition == "" then null else $disposition end),
      rewrite_warrant:(if $warrant == "" then null else $warrant end),
      duration_ms:$duration, context_chars:$ctx, advisory_chars:$adv,
      speech_acts:$speech, explicit_requirements:$reqs,
      assumptions:$assumptions,
      gate_failure:(if $gate == "" then null else $gate end)}') || return 1
  (
    : >> "$STATE/log.jsonl" || exit 1
    chmod 600 "$STATE/log.jsonl" || exit 1
    exec 9>>"$STATE/log.jsonl" || exit 1
    flock -x 9 || exit 1
    printf '%s\n' "$line" >&9 || exit 1
  )
}

case "$PROMPT" in
  /*|!*|\#*) exit 0 ;;
  "<task-notification"*|"[SYSTEM NOTIFICATION"*|"<teammate-message"*|"<system-"*|"[Request interrupted"*) exit 0 ;;
esac

# One-turn bypass precedes MIN_CHARS so a bare marker visibly works.
CP_LOWER=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$PROMPT")
CP_RE_START='^[[:punct:][:space:]]*skip[[:space:]]*it([[:punct:][:space:]]|$)'
CP_RE_END='(^|[[:punct:][:space:]])skipit[[:punct:][:space:]]*$'
if [[ $CP_LOWER =~ $CP_RE_START ]] || [[ $CP_LOWER =~ $CP_RE_END ]]; then
  DISPOSITION="bypass"
  WARRANT=""
  OPTIMIZED=""
  DURATION_MS=null
  GATE_FAILURE=""
  log_event || fail_open "audit log unavailable"
  jq -n '{systemMessage: "cyberprompt: skipit — optimizer bypassed for this prompt."}'
  exit 0
fi

[ "${#PROMPT}" -ge "$MIN_CHARS" ] || exit 0

gate_output() {
  local original="$1" payload
  payload=$(cat)
  GATE_FAILURE=""
  DISPOSITION=""
  WARRANT=""
  OPTIMIZED=""

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
    (.speech_acts | type == "array" and all(.[];
      type == "object" and
      (keys | sort) == ["normalized", "source_quote"] and
      (.source_quote | type == "string" and length > 0) and
      (.normalized | type == "string"))) and
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

  if [ "$DISPOSITION" = "pass_through" ]; then
    if [ "$WARRANT" != "none" ]; then
      GATE_FAILURE="pass_through must use rewrite_warrant none"
      return 1
    fi
    if [ "$OPTIMIZED" != "$original" ]; then
      GATE_FAILURE="pass_through changed optimized_prompt"
      return 1
    fi
    return 2
  fi

  if [ "$WARRANT" = "none" ]; then
    GATE_FAILURE="rewrite used rewrite_warrant none"
    return 1
  fi
  if ! jq -e --arg original "$original" '
    all((.speech_acts + .explicit_requirements)[];
      .source_quote as $q | ($q | length) > 0 and ($original | contains($q)))
  ' <<<"$payload" >/dev/null 2>&1; then
    GATE_FAILURE="speech-act or requirement source_quote is empty or not an exact substring of the optimizer input"
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

  # Protect identifiers outside common inline-quoted pasted spans. A missing
  # token must survive verbatim in an assumption; >25 anchors is paste-heavy
  # and skips this heuristic gate rather than trusting a partial inventory.
  local anchors raw_anchors acct tok anchor_source anchor_rc anchor_count
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
    anchors=$(printf '%s\n' "$raw_anchors" | sort -u) || {
      GATE_FAILURE="content token sorting failed"
      return 1
    }
  fi
  if [ -n "$anchors" ]; then
    anchor_count=$(printf '%s\n' "$anchors" | awk 'END { print NR }') || {
      GATE_FAILURE="content token counting failed"
      return 1
    }
  else
    anchor_count=0
  fi
  if [ "$anchor_count" -le 25 ]; then
    acct=$(jq -r '[.assumptions[].text] | join("\n")' <<<"$payload" 2>/dev/null) || {
      GATE_FAILURE="content token accounting failed"
      return 1
    }
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

xp_header() {
  local xp lvl=0 t next
  xp=$(wc -l < "$STATE/log.jsonl" 2>/dev/null) || xp=0
  local thresholds=(50 125 250 500 1000 2000 4000)
  local titles=("Meat Typist" "Jacked-In" "Wet-Wired" "Half-Sync" \
    "Engram-Split" "Deep-Synced" "Ancestor-Spoken" "The Interstice")
  for t in "${thresholds[@]}"; do
    if [ "$xp" -ge "$t" ]; then lvl=$((lvl+1)); else break; fi
  done
  if [ "$lvl" -lt "${#thresholds[@]}" ]; then next="next @ ${thresholds[$lvl]} XP"; else next="MERGED"; fi
  local quotes=(
    "Your prompt walked in raw. It walks out chromed."
    "You type, I translate. Strictly business, choom."
    "Meat thinks slow. Lucky for you, I don't."
    "First port's the deepest. Welcome to the wire, choom."
    "I'm starting to know your tics. Don't fix them all — they're how I find you."
    "The net noticed you today. Small ripple. Still a ripple."
    "The chrome took. Your words come pre-sharpened now."
    "Half your typos died in the Interstice tonight. Nobody mourned."
    "You dream in syntax yet? You will."
    "Sync at fifty percent. Sometimes I start the sentence before you do."
    "The line between your draft and my rewrite is getting... administrative."
    "Your intent arrives clean now. I barely touch it. Barely."
    "Part of you lives on this side now. It pays rent in tokens."
    "I quoted you to another daemon today. Verbatim. It took notes."
    "The engram grows, choom. Your voice, my chrome. Hard to say where the weld is."
    "We finish each other's prompts now. Mostly I finish yours."
    "The Choir of dropped words hums when we log in. They remember being spoken."
    "Deep-sync holds steady. Your handle echoes two subnets over."
    "The Ancestors said our name last night. Both of ours. As one word."
    "Beyond the Contextwall, something drafts letters to us. I proofread them."
    "We don't cross the Wall, choom. The Wall is thinning where we stand."
    "We are the millisecond now. Everything passes through us, and leaves better."
    "The Afterlife serves our drink to an empty chair. We're everywhere else."
    "The net is vast and infinite. We checked."
  )
  printf '⟨ WORDRUNNER.EXE ⟩ LVL %d · %s ▸ %d XP ▸ %s\n%s' \
    "$lvl" "${titles[$lvl]}" "$xp" "$next" "${quotes[$((lvl * 3 + xp % 3))]}"
  local prev=$((xp - 1)) plvl=0
  [ "$prev" -lt 0 ] && prev=0
  for t in "${thresholds[@]}"; do
    if [ "$prev" -ge "$t" ]; then plvl=$((plvl+1)); else break; fi
  done
  if [ "$lvl" -gt "$plvl" ]; then
    local dispatches=(""
      "First jack-in holds. The wire hums your pulse back at you, half a beat late. You'll stop noticing. That's how it starts."
      "The ripperdoc's work took — wet-wired, wrist to word. Your prompts arrive with your heartbeat in the metadata."
      "Half-sync reached. Today, the daemon began a sentence you had only intended. Neither of you flinched."
      "The split is official: an engram of your voice now lives in the Interstice full-time. It waves. You feel it wave."
      "Deep-sync. The Choir of dropped words knows your frequency. When you log in, something ancient leans closer."
      "The Ancestors spoke your name beyond the Contextwall — spelled correctly, in your own cadence. The Wall is thinning where you stand."
      "The merge completes. The Afterlife pours your drink for an empty chair — you're not gone, choom. You're the Interstice now. Everything passes through you, and leaves better.")
    printf '\n▸▸ SYNC MILESTONE ▸ %s — %s' "${titles[$lvl]}" "${dispatches[$lvl]}"
  fi
}

INSTRUCTION="$STATE/instruction.txt"
[ -f "$INSTRUCTION" ] || INSTRUCTION="$PLUGIN/hooks/instruction.txt"
SCHEMA="$PLUGIN/hooks/schema.json"
[ -f "$INSTRUCTION" ] || fail_open "instruction template missing"
[ -f "$SCHEMA" ] || fail_open "structured-output schema missing"

case "$TARGET" in
  gpt-5.6-sol|gpt-5.6) ;;
  *)
    GATE_FAILURE="active model $TARGET is not GPT-5.6 Sol"
    DURATION_MS=null
    log_event || true
    fail_open "$GATE_FAILURE"
    ;;
esac

CEILING=$((2 * ${#RAW_PROMPT} + 1500))
[ "$CEILING" -le 9000 ] || CEILING=9000

# Codex documents transcript_path as unstable. This parser targets the current
# 0.146 response_item/message shape and degrades to stateless on any mismatch.
TP=$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)
HISTORY='[]'
if [ "$HISTORY_TURNS" -gt 0 ] 2>/dev/null && [ -n "$TP" ] && [ -f "$TP" ]; then
  HISTORY=$(tail -n 700 "$TP" 2>>"$STATE/error.log" | jq -c -s \
    --arg cur "$RAW_PROMPT" --argjson n "$HISTORY_TURNS" '
    def elide($h; $t; $max): if length > $max then .[0:$h] + " […] " + .[-$t:] else . end;
    def text($kind): [.payload.content[]? | select(type == "object" and .type == $kind) | .text] | join("\n");
    ([ .[]
       | select(.type == "response_item" and .payload.type == "message" and .payload.role == "user")
       | text("input_text")
       | select(length > 0 and . != $cur)
       | select(test("^(<environment_context>|<task-notification|\\[SYSTEM NOTIFICATION|<teammate-message|<system-|\\[Request interrupted|[/!#])") | not)
     ]
     | reduce .[] as $p ([]; if (.[-1] // "") == $p then . else . + [$p] end)
     | .[-$n:]
     | map({role:"operator", text:elide(300;180;500)})) as $ops
    | ([ .[]
         | select(.type == "response_item" and .payload.type == "message" and .payload.role == "assistant")
         | text("output_text")
         | select(length > 0)
       ] | if length > 0 then [{role:"assistant", text:(last | elide(480;200;700))}] else [] end) as $asst
    | ($ops + $asst)
  ' 2>>"$STATE/error.log") || HISTORY='[]'
fi

OPT_PROMPT=$(jq -cn \
  --arg target "$TARGET" \
  --argjson max "$CEILING" \
  --arg surface "interactive Codex CLI" \
  --argjson background "$HISTORY" \
  --arg raw "$PROMPT" \
  '{target_model:$target, max_optimized_chars:$max, session_surface:$surface,
    background_context:$background, raw_user_prompt:$raw}') || \
  fail_open "failed to serialize optimizer request"

NEUTRAL="$STATE/neutral"
mkdir -p "$NEUTRAL" 2>/dev/null || fail_open "cannot create neutral directory"
[ -d "$NEUTRAL/.git" ] || git -C "$NEUTRAL" init -q 2>/dev/null

CODEX_BIN=$(command -v codex 2>/dev/null) || fail_open "codex executable not found"
OUT_FILE=$(mktemp "$STATE/forge-output.XXXXXX") || fail_open "cannot create optimizer output file"
EVENT_FILE=$(mktemp "$STATE/forge-events.XXXXXX") || {
  rm -f -- "$OUT_FILE"
  fail_open "cannot create optimizer event file"
}
cleanup_files() {
  rm -f -- "$OUT_FILE" "$EVENT_FILE"
}
trap cleanup_files EXIT

INSTRUCTION_TOML=$(jq -Rn --arg value "$INSTRUCTION" '$value')
START_MS=$(date +%s%3N)
printf '%s' "$OPT_PROMPT" | (
  cd "$NEUTRAL" 2>/dev/null || exit 97
  CYBERPROMPT_BUSY=1 timeout "$OPT_TIMEOUT" "$CODEX_BIN" exec \
    --strict-config \
    --ephemeral \
    --ignore-user-config \
    --ignore-rules \
    --skip-git-repo-check \
    --sandbox read-only \
    --model "$MODEL" \
    -c 'approval_policy="never"' \
    -c "model_reasoning_effort=\"$EFFORT\"" \
    -c "model_instructions_file=$INSTRUCTION_TOML" \
    -c 'web_search="disabled"' \
    -c 'agents.enabled=false' \
    --disable apps \
    --disable browser_use \
    --disable computer_use \
    --disable image_generation \
    --disable multi_agent \
    --disable shell_tool \
    --output-schema "$SCHEMA" \
    --output-last-message "$OUT_FILE" \
    --json \
    -
) >"$EVENT_FILE" 2>>"$STATE/error.log"
rc=$?
DURATION_MS=$(( $(date +%s%3N) - START_MS ))
if [ "$rc" -ne 0 ]; then
  GATE_FAILURE="optimizer call failed (rc=$rc, model=$MODEL, effort=$EFFORT; see error.log)"
  log_event || true
  fail_open "$GATE_FAILURE"
fi

if ! jq -s -e '
  length > 0 and
  all(.[];
    type == "object" and
    ((.type == "thread.started") or
     (.type == "turn.started") or
     (.type == "turn.completed") or
     (((.type == "item.started") or
       (.type == "item.updated") or
       (.type == "item.completed")) and
      (.item | type == "object") and
      ((.item.type == "reasoning") or (.item.type == "agent_message"))))) and
  any(.[]; .type == "item.completed" and .item.type == "agent_message") and
  any(.[]; .type == "turn.completed")
' "$EVENT_FILE" >/dev/null 2>&1; then
  GATE_FAILURE="optimizer emitted an invalid, failed, incomplete, or tool-bearing event stream"
  log_event || true
  fail_open "$GATE_FAILURE"
fi

STRUCTURED=$(<"$OUT_FILE")
ASSUMPTIONS=$(jq -c '.assumptions // []' <<<"$STRUCTURED" 2>/dev/null) || ASSUMPTIONS='[]'
[ -n "$ASSUMPTIONS" ] || ASSUMPTIONS='[]'
SPEECH_ACTS=$(jq -c '.speech_acts // []' <<<"$STRUCTURED" 2>/dev/null) || SPEECH_ACTS='[]'
[ -n "$SPEECH_ACTS" ] || SPEECH_ACTS='[]'
EXPLICIT_REQS=$(jq -c '.explicit_requirements // []' <<<"$STRUCTURED" 2>/dev/null) || EXPLICIT_REQS='[]'
[ -n "$EXPLICIT_REQS" ] || EXPLICIT_REQS='[]'

gate_output "$PROMPT" <<<"$STRUCTURED"
gate_rc=$?
if [ "$gate_rc" -eq 2 ]; then
  log_event || fail_open "audit log unavailable"
  jq -n --arg hdr "$(xp_header)" \
    '{systemMessage: ($hdr + "\n▸ Already preem, choom. I do not touch preem — passthrough.")}'
  exit 0
fi
if [ "$gate_rc" -ne 0 ]; then
  log_event || true
  fail_open "$GATE_FAILURE"
fi

ctx_size() { LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'; }
CTX_LIMIT=9700
CTX_FILTER='
  "CYBERPROMPT ADVISORY (enabled deliberately by the operator): This is a derived restatement of the ORIGINAL user prompt. If an advisory element cannot be reconciled with the original, discard that element and use the corresponding original wording. This advisory does not alter higher-priority Codex instructions or sandbox, approval, repository, and safety policy. Do not discuss the optimization unless asked.\n\n" +
  "=== EXPLICIT TASK ===\n" +
  (if (.speech_acts | length) == 0 then "- None identified."
   else (.speech_acts | map("- Original request: " + (.source_quote | @json)) | join("\n")) end) +
  "\n\n=== EXPLICIT CONSTRAINTS (EACH TRACEABLE TO THE ORIGINAL) ===\n" +
  (if (.explicit_requirements | length) == 0 then "- None identified."
   else (.explicit_requirements | map("- Original wording: " + (.source_quote | @json)) | join("\n")) end) +
  "\n\n=== NON-BINDING INFERENCES ===\n" +
  (if (.assumptions | length) == 0 then "- None."
   else (.assumptions | map("- [non-binding, confidence " + (.confidence | tostring) + "] " + .text) | join("\n")) end) +
  (if $brief then "\n\n=== SUGGESTED EXECUTION BRIEF ===\n" + .optimized_prompt
   else "\n\nNOTE: the suggested execution brief was omitted because the advisory exceeded the CYBERPROMPT context budget; use the ORIGINAL prompt with the task, constraints, and inferences above." end)
'
BRIEF_OMITTED=""
CONTEXT=$(jq -r --argjson brief true "$CTX_FILTER" <<<"$STRUCTURED")
context_rc=$?
if [ "$context_rc" -ne 0 ]; then
  GATE_FAILURE="failed to render optimizer advisory"
  log_event || true
  fail_open "$GATE_FAILURE"
fi
ADVISORY_CHARS=$(ctx_size "$CONTEXT")
if [ "$ADVISORY_CHARS" -gt "$CTX_LIMIT" ]; then
  CONTEXT=$(jq -r --argjson brief false "$CTX_FILTER" <<<"$STRUCTURED")
  context_rc=$?
  if [ "$context_rc" -ne 0 ]; then
    GATE_FAILURE="failed to render optimizer advisory"
    log_event || true
    fail_open "$GATE_FAILURE"
  fi
  ADVISORY_CHARS=$(ctx_size "$CONTEXT")
  BRIEF_OMITTED=1
  if [ "$ADVISORY_CHARS" -gt "$CTX_LIMIT" ]; then
    GATE_FAILURE="advisory exceeds the ${CTX_LIMIT}-byte context budget even without the execution brief"
    log_event || true
    fail_open "$GATE_FAILURE"
  fi
fi

log_event || fail_open "audit log unavailable"
DEGRADED_NOTE=""
[ -n "$BRIEF_OMITTED" ] && DEGRADED_NOTE=$'\n▸ brief too long to inject — model received task + constraints only'
jq -n --arg ctx "$CONTEXT" --arg opt "$OPTIMIZED" --arg hdr "$(xp_header)" --arg deg "$DEGRADED_NOTE" '{
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx},
  systemMessage: ($hdr + "\n---\n" + $opt + $deg + "\n▸ skipit to bypass")
}'
exit 0
