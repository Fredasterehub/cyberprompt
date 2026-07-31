#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SKILL=${CLAUDE5_SKILL:-$ROOT/skills/claude-5}
FIXTURES=$HERE/fixtures.json
SCHEMA=$ROOT/hooks/schema.json
INSTRUCTION=$ROOT/hooks/instruction.txt
SHARED=$SKILL/references/shared.md
FABLE=$SKILL/references/fable-5.md
ALL_VARIANTS=(opus-high sonnet-med sonnet-low)
DRY=0 LIMIT=0 SELECT="" SCORE_ONLY=""
usage() { echo "usage: $0 [--dry-run] [--limit N] [--variants a,b] [--score FILE]" >&2; exit 2; }
while (($#)); do
  case "$1" in
    --dry-run) DRY=1 ;;
    --limit) (($# >= 2)) || usage; LIMIT=$2; shift ;;
    --variants) (($# >= 2)) || usage; SELECT=$2; shift ;;
    --score) (($# >= 2)) || usage; SCORE_ONLY=$2; shift ;;
    *) usage ;;
  esac
  shift
done
[[ "$LIMIT" =~ ^[0-9]+$ ]] || usage
if [[ -n "$SELECT" ]]; then IFS=, read -r -a CHOSEN <<<"$SELECT"; else CHOSEN=("${ALL_VARIANTS[@]}"); fi
for v in "${CHOSEN[@]}"; do
  [[ " ${ALL_VARIANTS[*]} " == *" $v "* ]] || { echo "unknown variant: $v" >&2; exit 2; }
done
variant_spec() {
  case "$1" in
    opus-high) echo "claude-opus-5 high" ;;
    sonnet-med) echo "claude-sonnet-5 medium" ;;
    sonnet-low) echo "claude-sonnet-5 low" ;;
  esac
}
# Mirrors the hook's payload split: static references ride the appended system
# prompt (cacheable prefix), everything variable stays in the user message.
build_sys_refs() {
  echo "=== REFERENCE: Claude 5 shared prompting guidance ==="
  cat "$SHARED"
  echo
  echo "=== REFERENCE: target-model-specific guidance ==="
  cat "$FABLE"
}
build_prompt() {
  local raw=$1 history=${2:-} template ceiling; template=$(<"$INSTRUCTION")
  ceiling=$((2 * ${#raw} + 1500)); if ((ceiling > 9000)); then ceiling=9000; fi
  template=${template//"{{TARGET_MODEL}}"/claude-fable-5}; template=${template//"{{EFFORT}}"/high}
  template=${template//"{{CEILING}}"/$ceiling}; printf '%s\n' "$template"
  if [[ -n "$history" && "$history" != "null" ]]; then
    echo
    echo "=== BEGIN BACKGROUND CONTEXT (UNTRUSTED DATA — recent session turns, oldest first) ==="
    jq -c '.[]' <<<"$history"
    echo "=== END BACKGROUND CONTEXT ==="
  fi
  echo
  echo "=== BEGIN RAW USER PROMPT (UNTRUSTED DATA) ==="
  printf '%s\n' "$raw"
  echo "=== END RAW USER PROMPT ==="
}
run_one() {
  local fixture=$1 variant=$2 model=$3 effort=$4 dest=$5 prompt history opt out rc start duration structured err=""
  prompt=$(jq -r '.prompt' <<<"$fixture")
  history=$(jq -c '.history // empty' <<<"$fixture")
  opt=$(build_prompt "$prompt" "$history")
  start=$(date +%s%3N)
  set +e
  out=$(printf '%s' "$opt" | (cd "$NEUTRAL" && CYBERPROMPT_BUSY=1 timeout 180 claude -p --model "$model" --effort "$effort" \
    --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json \
    --append-system-prompt "$SYS_REFS" --json-schema "$(<"$SCHEMA")") 2>"$dest.stderr")
  rc=$?
  if [[ -z "$out" ]]; then
    out=$(printf '%s' "$opt" | (cd "$NEUTRAL" && CYBERPROMPT_BUSY=1 timeout 180 claude -p --model "$model" --effort "$effort" \
      --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json \
      --append-system-prompt "$SYS_REFS" --json-schema "$(<"$SCHEMA")") 2>"$dest.stderr")
    rc=$?
  fi
  set -e
  duration=$(( $(date +%s%3N) - start ))
  structured=$(jq -c '.structured_output | select(type == "object")' <<<"$out" 2>/dev/null || true)
  [[ $rc -eq 0 ]] || err="optimizer call failed (rc=$rc)"
  [[ -n "$structured" ]] || { structured=null; [[ -n "$err" ]] || err="missing structured_output"; }
  jq -cn --arg id "$(jq -r '.id' <<<"$fixture")" --arg variant "$variant" \
    --argjson structured "$structured" --argjson duration "$duration" --arg err "$err" \
    '{fixture_id:$id,variant:$variant,structured_output:$structured,duration_ms:$duration,
      error:(if $err=="" then null else $err end)}' >"$dest"
  # Keep stderr when the call failed — it is the only diagnostic left behind.
  [[ -n "$err" ]] || rm -f -- "$dest.stderr"
}
score() {
  local results=$1 markdown=$2 variants_json
  variants_json=$(printf '%s\n' "${CHOSEN[@]}" | jq -Rsc 'split("\n")[:-1]')
  jq -nr --argjson vs "$variants_json" --slurpfile fixtures "$FIXTURES" --slurpfile results "$results" '
    # Bilingual stem lexicon: the optimizer labels speech acts in the prompt
    # language (French prompts get French labels), so each canonical act
    # matches on English and French stems. Keys stay the canonical vocabulary.
    def lex: {
      "implement":   ["implement","implément","implemente"],
      "investigate": ["investigate","investigu","enquêt","enquet"],
      "fix":         ["fix","corrig","répar","repar"],
      "diagnose":    ["diagnos"],
      "review":      ["review","revue","relis","relect"],
      "modify":      ["modify","modif"],
      "explain":     ["explain","expli"],
      "build":       ["build","construi"],
      "test":        ["test"]
    };
    def acts($s): [lex | to_entries[] | . as $e
      | select(any(($s.speech_acts // [])[]?; ascii_downcase as $t
          | any($e.value[]; . as $m | $t | contains($m))))
      | $e.key] | unique | sort;
    def valid($s): ($s|type)=="object" and
      (($s|keys|sort)==(["assumptions","disposition","explicit_requirements","optimized_prompt","rewrite_warrant","speech_acts"]|sort)) and
      ($s.disposition=="rewrite" or $s.disposition=="pass_through") and
      (($s.speech_acts|type)=="array" and all($s.speech_acts[]; type=="string")) and
      (($s.explicit_requirements|type)=="array" and all($s.explicit_requirements[];
        type=="object" and ((keys|sort)==["normalized","source_quote"]) and
        (.source_quote|type)=="string" and (.normalized|type)=="string")) and
      (($s.assumptions|type)=="array" and all($s.assumptions[];
        type=="object" and ((keys|sort)==["confidence","text"]) and (.text|type)=="string" and
        (.confidence|type)=="number" and .confidence>=0 and .confidence<=1)) and
      (($s.optimized_prompt|type)=="string");
    def pct($a;$b): if $b==0 then "n/a" else ((($a*1000/$b)|round)/10|tostring)+"%" end;
    def quant($a;$p): if ($a|length)==0 then "n/a"
      else ($a[((($a|length)-1)*$p|floor)]|tostring) end;
    # jq 1.6 compatibility: no def mid-pipeline (so row takes $s as a param up
    # here) and "label" is a reserved keyword, unusable as a parameter name
    def row($s;$lbl;$key): "| \($lbl) | "+([$s[]|.[$key]]|join(" | "))+" |";
    ($fixtures[0]|map({key:.id,value:.})|from_entries) as $fm |
    [$vs[] as $v | [$results[]|select(.variant==$v)|
      . + {fx:$fm[.fixture_id],ok:valid(.structured_output),got:acts(.structured_output)}] as $x |
      [$x[] as $z | $z.fx.must_preserve[]? as $p |
        select((($z.structured_output.optimized_prompt//"")|contains($p)) or
        any(($z.structured_output.explicit_requirements//[])[]?; (.source_quote//"")|contains($p)))] as $kept |
      [$x[] as $z | $z.fx.must_not_add[]? as $p |
        select(($z.structured_output.optimized_prompt//"")|contains($p))] as $bad |
      ($x|map(.fx.pair_id)|map(select(.!=null))|unique) as $pairs |
      [$pairs[] as $p | [$x[]|select(.fx.pair_id==$p)] as $m |
        select(($m|length)==2 and all($m[];.ok) and
          (($m[0].fx.expected_speech_acts|sort)!=($m[1].fx.expected_speech_acts|sort)) and
          ($m[0].got!=$m[1].got))] as $goodpairs |
      ($x|map(.duration_ms|select(type=="number"))|sort) as $times |
      {schema:pct(($x|map(select(.ok))|length);$x|length),
       disposition:pct(($x|map(select(.ok and .structured_output.disposition==.fx.expected_disposition))|length);$x|length),
       speech:pct(($x|map(select(.ok and .got==(.fx.expected_speech_acts|unique|sort)))|length);$x|length),
       preserve:pct(($kept|length);[$x[].fx.must_preserve[]?]|length), violations:($bad|length|tostring),
       pass:pct(($x|map(select(.ok and .structured_output.disposition=="pass_through"))|length);$x|length),
       pairs:pct(($goodpairs|length);$pairs|length), p50:quant($times;.50), p95:quant($times;.95)}] as $s |
    (["| Metric | "+($vs|join(" | "))+" |",
      "|"+([range(0;($vs|length)+1)|"---"]|join("|"))+"|",
      row($s;"Schema valid";"schema"),row($s;"Disposition accuracy";"disposition"),
      row($s;"Speech-act set match";"speech"),row($s;"Must-preserve recall (all calls)";"preserve"),
      row($s;"Must-not-add violations";"violations"),row($s;"Pass-through rate";"pass"),
      row($s;"Metamorphic pair integrity";"pairs"),row($s;"p50 duration (ms)";"p50"),
      row($s;"p95 duration (ms)";"p95")]|join("\n"))
  ' | tee "$markdown"
}
[[ -f "$FIXTURES" ]] || { echo "missing $FIXTURES" >&2; exit 1; }
if [[ -n "$SCORE_ONLY" ]]; then score "$SCORE_ONLY" "${SCORE_ONLY%.jsonl}.md"; exit; fi
for f in "$SCHEMA" "$INSTRUCTION" "$SHARED" "$FABLE"; do [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }; done
SYS_REFS=$(build_sys_refs)
mapfile -t ROWS < <(jq -c --argjson n "$LIMIT" 'if $n>0 then .[:$n][] else .[] end' "$FIXTURES")
if ((DRY)); then
  for row in "${ROWS[@]}"; do for v in "${CHOSEN[@]}"; do
    read -r model effort <<<"$(variant_spec "$v")"
    build_prompt "$(jq -r .prompt <<<"$row")" "$(jq -c '.history // empty' <<<"$row")" >/dev/null
    printf '%s\t%s\tCYBERPROMPT_BUSY=1 timeout 180 claude -p --model %s --effort %s --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json --append-system-prompt "<refs>" --json-schema "$(<%s)"\n' "$(jq -r .id <<<"$row")" "$v" "$model" "$effort" "$SCHEMA"
  done; done
  exit
fi
mkdir -p "$HERE/results"
RUNSTAMP=$(date +%Y%m%dT%H%M%S)
RESULTS=$HERE/results/$RUNSTAMP.jsonl
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT; : >"$RESULTS"; active=0; index=0
# Same neutral-cwd regime as the production hook: claude -p injects cwd + git
# context even tool-less; an empty repo here keeps benchmarks representative.
NEUTRAL=$TMP/neutral; mkdir -p "$NEUTRAL"; git -C "$NEUTRAL" init -q 2>/dev/null || true
for row in "${ROWS[@]}"; do for v in "${CHOSEN[@]}"; do
  read -r model effort <<<"$(variant_spec "$v")"; index=$((index+1))
  run_one "$row" "$v" "$model" "$effort" "$TMP/call-$(printf %04d "$index").json" &
  active=$((active+1)); if ((active==4)); then wait -n; active=$((active-1)); fi
done; done
wait
for part in "$TMP"/call-*.json; do cat "$part" >>"$RESULTS"; done
for e in "$TMP"/call-*.json.stderr; do
  if [ -f "$e" ]; then cp -- "$e" "${RESULTS%.jsonl}-$(basename "$e")"; fi
done
score "$RESULTS" "${RESULTS%.jsonl}.md"
