#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE=$(cd "$HERE/.." && pwd)
SKILL=/fastpool/vms/subvol-101-disk-0/home/dev/.claude/skills/claude-5
FIXTURES=$HERE/fixtures.json
SCHEMA=$STATE/schema.json
INSTRUCTION=$STATE/instruction.txt
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
build_prompt() {
  local raw=$1 template; template=$(<"$INSTRUCTION")
  template=${template//"{{TARGET_MODEL}}"/claude-fable-5}; template=${template//"{{EFFORT}}"/high}; printf '%s\n' "$template"
  echo
  echo "=== REFERENCE: Claude 5 shared prompting guidance ==="
  cat "$SHARED"
  echo
  echo "=== REFERENCE: target-model-specific guidance ==="
  cat "$FABLE"
  echo
  echo "=== BEGIN RAW USER PROMPT (UNTRUSTED DATA) ==="
  printf '%s\n' "$raw"
  echo "=== END RAW USER PROMPT ==="
}
run_one() {
  local fixture=$1 variant=$2 model=$3 effort=$4 dest=$5 prompt opt out rc start duration structured err=""
  prompt=$(jq -r '.prompt' <<<"$fixture")
  opt=$(build_prompt "$prompt")
  start=$(date +%s%3N)
  set +e
  out=$(printf '%s' "$opt" | PROMPT_OPTIMIZER_BUSY=1 timeout 90 claude -p --model "$model" --effort "$effort" \
    --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json \
    --json-schema "$(<"$SCHEMA")" 2>"$dest.stderr")
  rc=$?
  if [[ -z "$out" ]]; then
    out=$(printf '%s' "$opt" | PROMPT_OPTIMIZER_BUSY=1 timeout 90 claude -p --model "$model" --effort "$effort" \
      --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json \
      --json-schema "$(<"$SCHEMA")" 2>"$dest.stderr")
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
  rm -f -- "$dest.stderr"
}
score() {
  local results=$1 markdown=$2 variants_json
  variants_json=$(printf '%s\n' "${CHOSEN[@]}" | jq -Rsc 'split("\n")[:-1]')
  jq -nr --argjson vs "$variants_json" --slurpfile fixtures "$FIXTURES" --slurpfile results "$results" '
    def vocab: ["implement","investigate","fix","diagnose","review","modify","explain","build","test"];
    def acts($s): [vocab[] as $v | select(any(($s.speech_acts // [])[]?;
      (ascii_downcase | contains($v)))) | $v] | unique | sort;
    def valid($s): ($s|type)=="object" and
      (($s|keys|sort)==(["assumptions","disposition","explicit_requirements","optimized_prompt","speech_acts"]|sort)) and
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
    def row($label;$key): "| \($label) | "+([$s[]|.[$key]]|join(" | "))+" |";
    (["| Metric | "+($vs|join(" | "))+" |",
      "|"+([range(0;($vs|length)+1)|"---"]|join("|"))+"|",
      row("Schema valid";"schema"),row("Disposition accuracy";"disposition"),
      row("Speech-act set match";"speech"),row("Must-preserve recall";"preserve"),
      row("Must-not-add violations";"violations"),row("Pass-through rate";"pass"),
      row("Metamorphic pair integrity";"pairs"),row("p50 duration (ms)";"p50"),
      row("p95 duration (ms)";"p95")]|join("\n"))
  ' | tee "$markdown"
}
[[ -f "$FIXTURES" ]] || { echo "missing $FIXTURES" >&2; exit 1; }
if [[ -n "$SCORE_ONLY" ]]; then score "$SCORE_ONLY" "${SCORE_ONLY%.jsonl}.md"; exit; fi
for f in "$SCHEMA" "$INSTRUCTION" "$SHARED" "$FABLE"; do [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }; done
mapfile -t ROWS < <(jq -c --argjson n "$LIMIT" 'if $n>0 then .[:$n][] else .[] end' "$FIXTURES")
if ((DRY)); then
  for row in "${ROWS[@]}"; do for v in "${CHOSEN[@]}"; do
    read -r model effort <<<"$(variant_spec "$v")"; build_prompt "$(jq -r .prompt <<<"$row")" >/dev/null
    printf '%s\t%s\tPROMPT_OPTIMIZER_BUSY=1 timeout 90 claude -p --model %s --effort %s --safe-mode --tools "" --strict-mcp-config --no-session-persistence --output-format json --json-schema "$(<%s)"\n' "$(jq -r .id <<<"$row")" "$v" "$model" "$effort" "$SCHEMA"
  done; done
  exit
fi
mkdir -p "$HERE/results"
RUNSTAMP=$(date +%Y%m%dT%H%M%S)
RESULTS=$HERE/results/$RUNSTAMP.jsonl
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT; : >"$RESULTS"; active=0; index=0
for row in "${ROWS[@]}"; do for v in "${CHOSEN[@]}"; do
  read -r model effort <<<"$(variant_spec "$v")"; index=$((index+1))
  run_one "$row" "$v" "$model" "$effort" "$TMP/call-$(printf %04d "$index").json" &
  active=$((active+1)); if ((active==4)); then wait -n; active=$((active-1)); fi
done; done
wait
for part in "$TMP"/call-*.json; do cat "$part" >>"$RESULTS"; done
score "$RESULTS" "${RESULTS%.jsonl}.md"
