#!/usr/bin/env bash
# Deterministic tests for hooks/cyberprompt.sh — the production gate, strip,
# history and fail-open paths, exercised end-to-end with zero API calls: each
# test runs the real hook under a scratch $HOME with a stub `claude` on PATH
# that records its stdin/argv and replays a canned response. Fast enough for
# every commit; the model-behavior fixtures live in run.sh, not here.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
HOOK=$ROOT/hooks/cyberprompt.sh
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT
PASS=0 FAIL=0 N=0

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FAIL [$1] $2" >&2; }
expect_contains()     { [[ "$1" == *"$2"* ]] && ok || bad "$3" "missing: $2"; }
expect_not_contains() { [[ "$1" != *"$2"* ]] && ok || bad "$3" "unexpected: $2"; }
expect_empty()        { [[ -z "$1" ]] && ok || bad "$2" "expected empty output, got: ${1:0:120}"; }
expect_file_absent()  { [[ ! -f "$1" ]] && ok || bad "$2" "stub was called but should not have been"; }
count_occurrences()   { grep -o -F -- "$2" <<<"$1" | wc -l; }

fresh_home() {
  N=$((N+1)); H=$TMP/home-$N; STATE=$H/.claude/cyberprompt
  mkdir -p "$STATE" "$H/.claude/skills" "$H/bin"
  cp -r "$ROOT/skills/claude-5" "$H/.claude/skills/claude-5"
  cp "$ROOT/hooks/instruction.txt" "$STATE/instruction.txt"
  cp "$ROOT/hooks/schema.json" "$STATE/schema.json"
  printf 'MODEL=claude-sonnet-5\nEFFORT=medium\nMIN_CHARS=80\nOPT_TIMEOUT=20\nHISTORY_TURNS=4\n' >"$STATE/config"
  touch "$STATE/enabled"
}

# stub_response <rc> <<<canned-stdout : installs the stub claude for $H
stub() {
  local rc=${1:-0}
  cat >"$H/canned.json"
  printf '#!/usr/bin/env bash\ncat > "%s/stub-stdin.txt"\nprintf "%%s\\n" "$@" > "%s/stub-argv.txt"\ncat "%s/canned.json"\nexit %s\n' \
    "$H" "$H" "$H" "$rc" >"$H/bin/claude"
  chmod +x "$H/bin/claude"
}

# structured <disposition> <optimized> <requirements-json> <assumptions-json> [warrant]
# Default warrant is a VALID one for rewrites: defaulting to "none" would flip
# every existing rewrite test into a fail-open and turn the suite unreadable.
structured() {
  local w=${5:-}
  if [ -z "$w" ]; then
    if [ "$1" = "rewrite" ]; then w=buried_constraint_hoisted; else w=none; fi
  fi
  jq -cn --arg d "$1" --arg o "$2" --argjson r "${3:-[]}" --argjson a "${4:-[]}" --arg w "$w" \
    '{structured_output: {disposition: $d, rewrite_warrant: $w, speech_acts: ["do the thing"],
      explicit_requirements: $r, assumptions: $a, optimized_prompt: $o}}'
}

# run_hook <input-json> [env VAR=...]; stdout captured, rc always tolerated
run_hook() {
  local out
  out=$(HOME="$H" PATH="$H/bin:$PATH" CLAUDE_PLUGIN_ROOT= CYBERPROMPT_BUSY= \
        bash "$HOOK" <<<"$1" 2>"$H/hook-stderr.txt") || true
  printf '%s' "$out"
}

input_json() { jq -cn --arg p "$1" '{prompt: $p, session_id: "gate-tests", effort: {level: "high"}}'; }

LONG_FR="le déploiement de la nuit est resté bloqué à moitié, remets la file de jobs en marche et préviens moi quand le backlog est entièrement vidé, sans redémarrer la base"

### 1-2. toggle + recursion guards
fresh_home; rm "$STATE/enabled"; stub 0 <<<'{}'
expect_empty "$(run_hook "$(input_json "$LONG_FR")")" "sentinel-off"
expect_file_absent "$H/stub-stdin.txt" "sentinel-off-nocall"
fresh_home; stub 0 <<<'{}'
OUT=$(HOME="$H" PATH="$H/bin:$PATH" CLAUDE_PLUGIN_ROOT= CYBERPROMPT_BUSY=1 bash "$HOOK" <<<"$(input_json "$LONG_FR")") || true
expect_empty "$OUT" "busy-guard"

### 3-6. skip classes
fresh_home; stub 0 <<<'{}'
expect_empty "$(run_hook "$(jq -cn --arg p "$LONG_FR" '{prompt:$p, agent_id:"sub-1"}')")" "subagent-skip"
expect_empty "$(run_hook "$(input_json "/help me with something long enough to pass the char floor easily")")" "slash-skip"
expect_empty "$(run_hook "$(input_json "<task-notification> some machine payload that is definitely long enough to pass the floor")")" "machine-skip"
expect_empty "$(run_hook "$(input_json "trop court")")" "minchars-skip"
expect_file_absent "$H/stub-stdin.txt" "skips-nocall"

### 7. whisper artifact strip + negative control
fresh_home
structured rewrite "rewrite of the deploy ask" '[]' '[]' | stub 0
ART_PROMPT="$LONG_FR
Sous-titres réalisés par la communauté d'Amara.org"
run_hook "$(input_json "$ART_PROMPT")" >/dev/null
STDIN=$(cat "$H/stub-stdin.txt")
expect_not_contains "$STDIN" "Amara.org" "artifact-stripped"
expect_contains "$STDIN" "file de jobs" "artifact-strip-keeps-text"
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "le bug affiche Sous-titres réalisés par la communauté d'Amara.org au milieu de la sortie du transcripteur, trouve d'où ça vient")" >/dev/null
expect_contains "$(cat "$H/stub-stdin.txt")" "Amara.org" "artifact-embedded-survives"

### 8. artifact-only prompt: exits untouched, no call
fresh_home; stub 0 <<<'{}'
expect_empty "$(run_hook "$(input_json "Sous-titres réalisés par la communauté d'Amara.org
Merci d'avoir regardé cette vidéo
Thank you for watching")")" "artifact-only-passthrough"
expect_file_absent "$H/stub-stdin.txt" "artifact-only-nocall"

### 9. repetition collapse (5x -> 1)
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
REP="relance le worker de synchronisation qui tourne en boucle sur la même erreur et conserve les journaux existants pour le diagnostic"
run_hook "$(input_json "$REP
$REP
$REP
$REP
$REP")" >/dev/null
C=$(count_occurrences "$(cat "$H/stub-stdin.txt")" "$REP")
[[ "$C" -eq 1 ]] && ok || bad "repetition-collapse" "expected 1 occurrence, got $C"

### 10. rewrite happy path
fresh_home
structured rewrite "Remets la file de jobs en marche sans redémarrer la base, et signale quand le backlog est vidé." \
  '[{"source_quote":"sans redémarrer la base","normalized":"ne pas redémarrer la base"}]' '[]' | stub 0
OUT=$(run_hook "$(input_json "$LONG_FR")")
expect_contains "$OUT" "hookSpecificOutput" "rewrite-additional-context"
expect_contains "$OUT" "CYBERPROMPT ADVISORY" "rewrite-advisory-header"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"disposition":"rewrite"' "rewrite-logged"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"context_chars":' "rewrite-context-chars-field"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"speech_acts":["do the thing"]' "log-speech-acts"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"source_quote":"sans redémarrer la base"' "log-explicit-reqs"

### 11. pass_through path
fresh_home
structured pass_through "$LONG_FR" '[]' '[]' | stub 0
OUT=$(run_hook "$(input_json "$LONG_FR")")
expect_contains "$OUT" "suppressOutput" "passthrough-suppress"
expect_not_contains "$OUT" "hookSpecificOutput" "passthrough-no-context"

### 12. empty source_quote (regression for 1b098d3)
fresh_home
structured rewrite "une réécriture avec exigence inventée" \
  '[{"source_quote":"","normalized":"use Kubernetes"}]' '[]' | stub 0
OUT=$(run_hook "$(input_json "$LONG_FR")")
expect_contains "$OUT" "source_quote is empty" "empty-quote-blocked"
expect_contains "$OUT" "original prompt passed through unchanged" "empty-quote-fails-open"

### 13. invented quote
fresh_home
structured rewrite "réécriture" \
  '[{"source_quote":"use Kubernetes in prod","normalized":"k8s"}]' '[]' | stub 0
expect_contains "$(run_hook "$(input_json "$LONG_FR")")" \
  "not an exact substring" "invented-quote-blocked"

### 14. ceiling
fresh_home
BIG=$(printf 'x%.0s' $(seq 1 9500))
structured rewrite "$BIG" '[]' '[]' | stub 0
expect_contains "$(run_hook "$(input_json "$LONG_FR")")" "character ceiling" "ceiling-blocked"

### 15. garbage output -> schema failure
fresh_home; stub 0 <<<'this is not json at all'
expect_contains "$(run_hook "$(input_json "$LONG_FR")")" \
  "schema validation" "garbage-schema-fail"

### 16. optimizer rc != 0 -> fail open
fresh_home; stub 3 <<<'{}'
expect_contains "$(run_hook "$(input_json "$LONG_FR")")" \
  "optimizer call failed (rc=3" "rc-fail-open"

### 17-18. retention gate: silent drop fails, accounted drop passes
ANCHOR_PROMPT="corrige le script src/metrics/export.py pour que le flag --dry-run soit le défaut, sans changer la sortie existante ni les autres options du script"
fresh_home
structured rewrite "Corrige le script d'export des métriques pour que la simulation soit le comportement par défaut." \
  '[{"source_quote":"sans changer la sortie existante","normalized":"sortie inchangée"}]' '[]' | stub 0
expect_contains "$(run_hook "$(input_json "$ANCHOR_PROMPT")")" \
  "content token dropped without accounting" "retention-silent-drop"
fresh_home
structured rewrite "Corrige le script d'export des métriques pour que la simulation soit le comportement par défaut." \
  '[{"source_quote":"sans changer la sortie existante","normalized":"sortie inchangée"}]' \
  '[{"text":"Le script visé est src/metrics/export.py et le flag concerné est --dry-run.","confidence":0.9}]' | stub 0
OUT=$(run_hook "$(input_json "$ANCHOR_PROMPT")")
expect_contains "$OUT" "hookSpecificOutput" "retention-accounted-ships"
expect_not_contains "$OUT" "content token dropped" "retention-accounted-clean"

### 19. history slice: operators + assistant in, machine turns and current prompt out
fresh_home
TP=$H/transcript.jsonl
cat >"$TP" <<'EOT'
{"type":"user","message":{"content":"premier vrai prompt operateur sur le pipeline de synchronisation"}}
{"type":"user","message":{"content":"Another Claude session sent a message:\n<teammate-message teammate_id=\"x\">hello</teammate-message>"}}
{"type":"user","message":{"content":"This session is being continued from a previous conversation. Summary: lots of machine text"}}
{"type":"user","isCompactSummary":true,"message":{"content":"another continuation body that must never appear"}}
{"type":"assistant","message":{"model":"claude-fable-5","content":[{"type":"text","text":"reponse assistant sur la synchronisation"},{"type":"tool_use","name":"Bash","input":{}}]}}
{"type":"user","message":{"content":"deuxieme vrai prompt operateur a propos du meme pipeline"}}
EOT
structured rewrite "x" '[]' '[]' | stub 0
IN=$(jq -cn --arg p "$LONG_FR" --arg tp "$TP" '{prompt:$p, transcript_path:$tp, session_id:"gate-tests", effort:{level:"high"}}')
run_hook "$IN" >/dev/null
STDIN=$(cat "$H/stub-stdin.txt")
expect_contains "$STDIN" "BEGIN BACKGROUND CONTEXT" "history-block-present"
expect_contains "$STDIN" "premier vrai prompt operateur" "history-op1"
expect_contains "$STDIN" "deuxieme vrai prompt operateur" "history-op2"
expect_contains "$STDIN" "reponse assistant sur la synchronisation" "history-assistant"
expect_not_contains "$STDIN" "teammate-message" "history-no-teammate"
expect_not_contains "$STDIN" "being continued" "history-no-compaction"
expect_not_contains "$STDIN" "never appear" "history-no-compact-flag"
C=$(count_occurrences "$STDIN" "file de jobs")
[[ "$C" -eq 1 ]] && ok || bad "history-excludes-current" "current prompt appears $C times (background leak)"

### 20. no transcript -> stateless payload, still ships
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "$LONG_FR")" >/dev/null
expect_not_contains "$(cat "$H/stub-stdin.txt")" "BEGIN BACKGROUND CONTEXT" "stateless-no-block"

### 21. stale template -> legacy payload: refs inline, no system prompt, no history
fresh_home
printf 'You are a prompt optimizer. Output only JSON per the schema.\nTARGET MODEL: {{TARGET_MODEL}} (effort {{EFFORT}})\n' >"$STATE/instruction.txt"
structured rewrite "x" '[]' '[]' | stub 0
IN=$(jq -cn --arg p "$LONG_FR" --arg tp "$TP" '{prompt:$p, transcript_path:$tp, session_id:"gate-tests", effort:{level:"high"}}')
run_hook "$IN" >/dev/null
STDIN=$(cat "$H/stub-stdin.txt"); ARGV=$(cat "$H/stub-argv.txt")
expect_contains "$STDIN" "=== REFERENCE: Claude 5 shared prompting guidance ===" "stale-refs-inline"
expect_not_contains "$ARGV" "append-system-prompt" "stale-no-sysprompt"
expect_not_contains "$STDIN" "BEGIN BACKGROUND CONTEXT" "stale-no-history"
expect_contains "$STDIN" "Hard length budget" "stale-ceiling-fallback"

### 22. current template -> refs via system prompt only
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "$LONG_FR")" >/dev/null
expect_contains "$(cat "$H/stub-argv.txt")" "append-system-prompt" "current-sysprompt-arg"
expect_not_contains "$(cat "$H/stub-stdin.txt")" "=== REFERENCE: Claude 5 shared" "current-no-inline-refs"

### 23. WORDRUNNER chrome strip: pasted grey-block banners drop, mentions survive
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
NBSP=$(printf '\302\240')
CHROME_PROMPT="$LONG_FR
  ⎿ ${NBSP}UserPromptSubmit says: ⟨ WORDRUNNER.EXE ⟩ LVL 1 · Jacked-In ▸ 99 XP ▸ next @ 125 XP
     ▸▸ SYNC MILESTONE ▸ Jacked-In — First jack-in holds."
run_hook "$(input_json "$CHROME_PROMPT")" >/dev/null
STDIN=$(cat "$H/stub-stdin.txt")
expect_not_contains "$STDIN" "WORDRUNNER.EXE" "chrome-stripped"
expect_not_contains "$STDIN" "SYNC MILESTONE" "chrome-milestone-stripped"
expect_contains "$STDIN" "file de jobs" "chrome-strip-keeps-text"
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "le header ⟨ WORDRUNNER.EXE ⟩ LVL 3 · Half-Sync est mal aligné sur la page, corrige le rendu du bandeau")" >/dev/null
expect_contains "$(cat "$H/stub-stdin.txt")" "WORDRUNNER.EXE" "chrome-embedded-survives"

### 24. skipit bypass: start/end forms, two-word rules, ordering vs MIN_CHARS
fresh_home; stub 0 <<<'{}'
OUT=$(run_hook "$(input_json "skipit $LONG_FR")")
expect_contains "$OUT" "skipit" "bypass-start"
expect_file_absent "$H/stub-stdin.txt" "bypass-start-nocall"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"disposition":"bypass"' "bypass-logged"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"duration_ms":null' "bypass-duration-null"
fresh_home; stub 0 <<<'{}'
expect_contains "$(run_hook "$(input_json "$LONG_FR, skipit.")")" "systemMessage" "bypass-end"
expect_file_absent "$H/stub-stdin.txt" "bypass-end-nocall"
fresh_home; stub 0 <<<'{}'
expect_contains "$(run_hook "$(input_json "Skip it. $LONG_FR")")" "systemMessage" "bypass-twoword-start"
expect_file_absent "$H/stub-stdin.txt" "bypass-twoword-nocall"
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "$LONG_FR, on peut skip it plus tard")" >/dev/null
expect_contains "$(cat "$H/stub-stdin.txt")" "file de jobs" "bypass-twoword-trailing-optimizes"
fresh_home
structured rewrite "x" '[]' '[]' | stub 0
run_hook "$(input_json "skip iterating over the archived jobs and only replay the failed ones from the last visible batch")" >/dev/null
expect_contains "$(cat "$H/stub-stdin.txt")" "skip iterating" "bypass-negative-control"
fresh_home; stub 0 <<<'{}'
expect_contains "$(run_hook "$(input_json "skipit")")" "systemMessage" "bypass-below-minchars"
expect_file_absent "$H/stub-stdin.txt" "bypass-below-minchars-nocall"

### 25. advisory overflow ladder: rung 2 drops the brief, rung 3 fails open
BIGA=$(printf 'a%.0s' $(seq 1 5000))          # zero retention anchors, CEILING caps at 9000
fresh_home
A800=$(jq -cn --arg t "$(printf 'z%.0s' $(seq 1 800))" '[{"text":$t,"confidence":0.9}]')
structured rewrite "$(printf 'y%.0s' $(seq 1 8990))" '[]' "$A800" | stub 0
OUT=$(run_hook "$(input_json "$BIGA")")
expect_contains "$OUT" "hookSpecificOutput" "overflow-tier2-ships"
expect_not_contains "$OUT" "=== SUGGESTED EXECUTION BRIEF ===" "overflow-tier2-no-brief"
expect_contains "$OUT" "execution brief was omitted" "overflow-tier2-note"
expect_contains "$OUT" "brief too long to inject" "overflow-tier2-operator-marker"
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"advisory_chars":' "overflow-advisory-chars-logged"
fresh_home
A9800=$(jq -cn --arg t "$(printf 'z%.0s' $(seq 1 9800))" '[{"text":$t,"confidence":0.9}]')
structured rewrite "une petite réécriture" '[]' "$A9800" | stub 0
OUT=$(run_hook "$(input_json "$BIGA")")
expect_contains "$OUT" "injection limit" "overflow-tier3-fails-open"
expect_not_contains "$OUT" "hookSpecificOutput" "overflow-tier3-no-context"

### 26. restraint gate: rewrite must name a warrant, warrant is logged
fresh_home
structured rewrite "une réécriture sans justification" '[]' '[]' none | stub 0
OUT=$(run_hook "$(input_json "$LONG_FR")")
expect_contains "$OUT" "rewrite_warrant is none" "warrant-none-blocked"
expect_contains "$OUT" "original prompt passed through unchanged" "warrant-none-fails-open"
fresh_home
structured rewrite "Remets la file de jobs en marche sans redémarrer la base." '[]' '[]' referent_bound | stub 0
run_hook "$(input_json "$LONG_FR")" >/dev/null
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"rewrite_warrant":"referent_bound"' "warrant-logged"
fresh_home
structured rewrite "x" '[]' '[]' made_it_clearer | stub 0
expect_contains "$(run_hook "$(input_json "$LONG_FR")")" "schema validation" "warrant-unknown-rejected"
fresh_home
structured pass_through "$LONG_FR" '[]' '[]' | stub 0
run_hook "$(input_json "$LONG_FR")" >/dev/null
expect_contains "$(tail -1 "$STATE/log.jsonl")" '"rewrite_warrant":"none"' "warrant-passthrough-none"

echo
echo "gate-tests: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
