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

# Never rewrite subagent prompts — only the operator's own messages.
[ -n "$(jq -r '.agent_id // empty' <<<"$INPUT")" ] && exit 0

PROMPT=$(jq -r '.prompt // empty' <<<"$INPUT")
[ -z "$PROMPT" ] && exit 0

MODEL=claude-sonnet-5
EFFORT=medium
MIN_CHARS=80
OPT_TIMEOUT=180
[ -f "$STATE/config" ] && . "$STATE/config"
# claude-5 skill: explicit override > plugin-bundled copy > legacy seeded copy.
SKILL="${CLAUDE5_SKILL:-${PLUGIN:+$PLUGIN/skills/claude-5}}"
SKILL="${SKILL:-$HOME/.claude/skills/claude-5}"

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
[ "${#PROMPT}" -lt "$MIN_CHARS" ] && exit 0

fail_open() {
  jq -n --arg m "$1" \
    '{systemMessage: ("cyberprompt: " + $m + " — original prompt passed through unchanged.")}'
  exit 0
}

log_event() {
  local line
  line=$(jq -cn --arg ts "$(date -Is)" \
         --arg sid "$(jq -r '.session_id // ""' <<<"$INPUT")" \
         --arg model "$MODEL" --arg target "$TARGET" \
         --arg original "$PROMPT" --arg optimized "${OPTIMIZED:-}" \
         --arg disposition "${DISPOSITION:-}" \
         --argjson duration "${DURATION_MS:-0}" \
         --arg gate "${GATE_FAILURE:-}" \
    '{ts:$ts, session:$sid, optimizer_model:$model, target_model:$target,
      original:$original, optimized:$optimized,
      disposition:(if $disposition == "" then null else $disposition end),
      duration_ms:$duration,
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

gate_output() {
  local original="$1" payload
  payload=$(cat)
  GATE_FAILURE=""
  DISPOSITION=""
  OPTIMIZED=""

  if ! jq -e '
    type == "object" and
    (keys | sort) == ([
      "assumptions", "disposition", "explicit_requirements",
      "optimized_prompt", "speech_acts"
    ] | sort) and
    (.disposition == "rewrite" or .disposition == "pass_through") and
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
  OPTIMIZED=$(jq -r '.optimized_prompt' <<<"$payload")
  [ "$DISPOSITION" = "pass_through" ] && return 2

  if ! jq -e --arg original "$original" '
    all(.explicit_requirements[]; .source_quote as $q | $original | contains($q))
  ' <<<"$payload" >/dev/null 2>&1; then
    GATE_FAILURE="source_quote is not an exact substring of the original prompt"
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
CEILING=$((2 * ${#PROMPT} + 1500))
[ "$CEILING" -gt 9000 ] && CEILING=9000

OPT_PROMPT=$(
  sed -e "s|{{TARGET_MODEL}}|$TARGET|" -e "s|{{EFFORT}}|$SESSION_EFFORT|" \
      -e "s|{{CEILING}}|$CEILING|" "$INSTRUCTION"
  # Stale or user-customized templates may predate {{CEILING}}; the budget must
  # reach the model regardless, or the gate rejects output it was never warned about.
  grep -q '{{CEILING}}' "$INSTRUCTION" || \
    printf 'Hard length budget: optimized_prompt must not exceed %s characters; if a faithful rewrite cannot fit, choose pass_through.\n' "$CEILING"
  echo
  echo "=== REFERENCE: Claude 5 shared prompting guidance ==="
  cat "$SKILL/references/shared.md"
  if [ -n "$REF" ] && [ -f "$REF" ]; then
    echo
    echo "=== REFERENCE: target-model-specific guidance ==="
    cat "$REF"
  fi
  echo
  echo "=== BEGIN RAW USER PROMPT (UNTRUSTED DATA) ==="
  printf '%s\n' "$PROMPT"
  echo "=== END RAW USER PROMPT ==="
)

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
      --output-format json --json-schema "$(<"$SCHEMA")") 2>>"$STATE/error.log")
rc=$?
DURATION_MS=$(( $(date +%s%3N) - START_MS ))
if [ "$rc" -ne 0 ]; then
  GATE_FAILURE="optimizer call failed (rc=$rc, model=$MODEL, see error.log)"
  log_event
  fail_open "$GATE_FAILURE"
fi

STRUCTURED=$(jq -c '.structured_output | select(type == "object")' <<<"$RESPONSE" 2>/dev/null)
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
log_event

CONTEXT=$(jq -r '
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
  "\n\n=== SUGGESTED EXECUTION BRIEF ===\n" + .optimized_prompt
' <<<"$STRUCTURED")
context_rc=$?
[ "$context_rc" -ne 0 ] && fail_open "failed to render optimizer advisory"

jq -n --arg ctx "$CONTEXT" --arg opt "$OPTIMIZED" --arg hdr "$(xp_header)" '{
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx},
  systemMessage: ($hdr + "\n---\n" + $opt),
  suppressOutput: true
}'
exit 0
