#!/usr/bin/env bash
# Real-model CyberPrompt evaluation for GPT-5.6 Sol. This runner is separate
# from the Claude harness and mirrors the production Codex forge invocation.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PLUGIN=${CYBERPROMPT_CODEX_PLUGIN:-$ROOT/plugins/cyberprompt}
FIXTURES=$HERE/fixtures.json
SCHEMA=$PLUGIN/hooks/schema.json
INSTRUCTION=$PLUGIN/hooks/instruction.txt
MODEL=gpt-5.6-sol
ALL_VARIANTS=(sol-low sol-medium)
SMOKE_IDS=(
  p1-implement
  p1-investigate
  clear-implement
  ctx-reference-resolution
  ctx-topic-switch
  repair-fr
)

DRY=0
SMOKE=0
LIMIT=0
SELECT=""
JOBS=2
CALL_TIMEOUT=180
OUTPUT_DIR=""

usage() {
  cat >&2 <<'EOF'
usage: harness/run-codex.sh [options]

Options:
  --dry-run             Print the planned calls as JSONL; do not call Codex.
  --smoke               Use a fixed six-fixture smoke set (12 calls by default).
  --limit N             Use only the first N fixtures (cannot combine with --smoke).
  --variants LIST       Comma-separated sol-low,sol-medium (default: both).
  --jobs N              Maximum concurrent calls, 1-8 (default: 2).
  --timeout SECONDS     Per-call timeout (default: 180).
  --output-dir DIR      New directory for this run (must not already exist).
  -h, --help            Show this help.

The default is the full fixed fixture set. Use --smoke before spending on a
full comparison. Results include results.jsonl, summary.json, summary.md, and
one isolated directory per variant and fixture.
EOF
}

die() {
  printf 'run-codex: %s\n' "$*" >&2
  exit 2
}

while (($#)); do
  case "$1" in
    --dry-run) DRY=1 ;;
    --smoke) SMOKE=1 ;;
    --limit)
      (($# >= 2)) || die "--limit requires a value"
      LIMIT=$2
      shift
      ;;
    --variants)
      (($# >= 2)) || die "--variants requires a value"
      SELECT=$2
      shift
      ;;
    --jobs)
      (($# >= 2)) || die "--jobs requires a value"
      JOBS=$2
      shift
      ;;
    --timeout)
      (($# >= 2)) || die "--timeout requires a value"
      CALL_TIMEOUT=$2
      shift
      ;;
    --output-dir)
      (($# >= 2)) || die "--output-dir requires a value"
      OUTPUT_DIR=$2
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ "$LIMIT" =~ ^[0-9]+$ ]] || die "--limit must be a non-negative integer"
[[ "$JOBS" =~ ^[1-8]$ ]] || die "--jobs must be between 1 and 8"
[[ "$CALL_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
((SMOKE == 0 || LIMIT == 0)) || die "--smoke and --limit cannot be combined"

if [[ -n "$SELECT" ]]; then
  IFS=, read -r -a CHOSEN <<<"$SELECT"
else
  CHOSEN=("${ALL_VARIANTS[@]}")
fi
(( ${#CHOSEN[@]} > 0 )) || die "at least one variant is required"
for variant in "${CHOSEN[@]}"; do
  [[ " ${ALL_VARIANTS[*]} " == *" $variant "* ]] || die "unknown variant: $variant"
done

for required in "$FIXTURES" "$SCHEMA" "$INSTRUCTION"; do
  [[ -f "$required" ]] || die "missing required file: $required"
done
command -v jq >/dev/null 2>&1 || die "jq is required"
CODEX_BIN=$(command -v codex 2>/dev/null) || die "codex is required"

variant_effort() {
  case "$1" in
    sol-low) printf 'low\n' ;;
    sol-medium) printf 'medium\n' ;;
    *) return 1 ;;
  esac
}

build_prompt() {
  local fixture=$1 raw history ceiling
  raw=$(jq -r '.prompt' <<<"$fixture")
  history=$(jq -c '.history // []' <<<"$fixture")
  ceiling=$((2 * ${#raw} + 1500))
  ((ceiling <= 9000)) || ceiling=9000

  jq -cn --arg target "$MODEL" --argjson max "$ceiling" \
    --arg surface "interactive Codex CLI" --argjson background "$history" \
    --arg raw "$raw" '{target_model:$target, max_optimized_chars:$max,
      session_surface:$surface, background_context:$background,
      raw_user_prompt:$raw}'
}

select_fixtures() {
  if ((SMOKE)); then
    jq -c --argjson ids "$(printf '%s\n' "${SMOKE_IDS[@]}" | jq -Rsc 'split("\n")[:-1]')" '
      . as $all
      | $ids[] as $id
      | ($all[] | select(.id == $id))
    ' "$FIXTURES"
  elif ((LIMIT > 0)); then
    jq -c --argjson n "$LIMIT" '.[:$n][]' "$FIXTURES"
  else
    jq -c '.[]' "$FIXTURES"
  fi
}

mapfile -t ROWS < <(select_fixtures)
(( ${#ROWS[@]} > 0 )) || die "fixture selection is empty"

if ((SMOKE)); then
  for expected_id in "${SMOKE_IDS[@]}"; do
    found=0
    for row in "${ROWS[@]}"; do
      [[ "$(jq -r '.id' <<<"$row")" == "$expected_id" ]] && found=1
    done
    ((found)) || die "smoke fixture is missing: $expected_id"
  done
fi

INSTRUCTION_TOML=$(jq -Rn --arg value "$INSTRUCTION" '$value')
COMMAND_JSON=$(jq -cn --arg bin "$CODEX_BIN" --arg model "$MODEL" \
  --arg schema "$SCHEMA" --arg instruction "$INSTRUCTION" '[
    $bin, "exec", "--strict-config", "--ephemeral", "--ignore-user-config", "--ignore-rules",
    "--skip-git-repo-check", "--sandbox", "read-only",
    "--model", $model, "-c", "approval_policy=\"never\"",
    "-c", "model_reasoning_effort=<effort>",
    "-c", ("model_instructions_file=" + ($instruction | @json)),
    "-c", "web_search=\"disabled\"", "-c", "agents.enabled=false",
    "--disable", "apps", "--disable", "browser_use",
    "--disable", "computer_use", "--disable", "image_generation",
    "--disable", "multi_agent", "--disable", "shell_tool",
    "--output-schema", $schema, "--output-last-message", "<output>",
    "--json", "-"
  ]')

if ((DRY)); then
  for row in "${ROWS[@]}"; do
    fixture_id=$(jq -r '.id' <<<"$row")
    raw=$(jq -r '.prompt' <<<"$row")
    ceiling=$((2 * ${#raw} + 1500))
    ((ceiling <= 9000)) || ceiling=9000
    history_count=$(jq '.history // [] | length' <<<"$row")
    for variant in "${CHOSEN[@]}"; do
      effort=$(variant_effort "$variant")
      jq -cn --arg fixture_id "$fixture_id" --arg variant "$variant" \
        --arg model "$MODEL" --arg effort "$effort" \
        --argjson raw_chars "${#raw}" --argjson ceiling "$ceiling" \
        --argjson history_items "$history_count" --argjson command "$COMMAND_JSON" '
        {dry_run:true, fixture_id:$fixture_id, variant:$variant,
         model:$model, effort:$effort, raw_prompt_chars:$raw_chars,
         max_optimized_chars:$ceiling, history_items:$history_items,
         command_template:$command}'
    done
  done
  exit 0
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  RUNSTAMP=$(date -u +%Y%m%dT%H%M%SZ)
  OUTPUT_DIR=$HERE/results/codex/$RUNSTAMP-$$
fi
[[ ! -e "$OUTPUT_DIR" ]] || die "output directory already exists: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
RUN_DIR=$(cd "$OUTPUT_DIR" && pwd)

WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cyberprompt-codex-eval.XXXXXX")
cleanup() {
  case "$WORK_ROOT" in
    "${TMPDIR:-/tmp}"/cyberprompt-codex-eval.*) rm -rf -- "$WORK_ROOT" ;;
  esac
}
trap cleanup EXIT

run_one() {
  local fixture=$1 variant=$2 effort=$3 call_dir=$4 work_dir=$5
  local prompt_file events_file output_file stderr_file result_file
  local start_ms duration_ms rc event_valid tool_events failure_events
  local structured usage error=""

  prompt_file=$call_dir/input.txt
  events_file=$call_dir/events.jsonl
  output_file=$call_dir/structured.json
  stderr_file=$call_dir/stderr.log
  result_file=$call_dir/result.json
  mkdir -p "$call_dir" "$work_dir"
  git -C "$work_dir" init -q 2>/dev/null || true
  build_prompt "$fixture" >"$prompt_file"

  start_ms=$(date +%s%3N)
  set +e
  (
    cd "$work_dir" || exit 97
    CYBERPROMPT_BUSY=1 timeout "$CALL_TIMEOUT" "$CODEX_BIN" exec \
      --strict-config \
      --ephemeral \
      --ignore-user-config \
      --ignore-rules \
      --skip-git-repo-check \
      --sandbox read-only \
      --model "$MODEL" \
      -c 'approval_policy="never"' \
      -c "model_reasoning_effort=\"$effort\"" \
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
      --output-last-message "$output_file" \
      --json \
      - <"$prompt_file"
  ) >"$events_file" 2>"$stderr_file"
  rc=$?
  set -e
  duration_ms=$(( $(date +%s%3N) - start_ms ))

  event_valid=false
  tool_events=0
  failure_events=0
  usage=null
  if jq -s -e 'length > 0 and all(.[]; type == "object")' \
      "$events_file" >/dev/null 2>&1; then
    tool_events=$(jq -s '[.[] | select(
      ((.type == "item.started" or .type == "item.updated" or .type == "item.completed") and
       ((.item.type // "") != "reasoning" and (.item.type // "") != "agent_message"))
    )] | length' "$events_file")
    failure_events=$(jq -s '[.[] | select(.type == "error" or .type == "turn.failed")] | length' "$events_file")
    usage=$(jq -cs '[.[] | select(.type == "turn.completed") | .usage // empty] | last // null' "$events_file")
    if jq -s -e '
      all(.[];
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
    ' "$events_file" >/dev/null 2>&1; then
      event_valid=true
    fi
  fi

  structured=null
  if [[ -s "$output_file" ]] && jq -e 'type == "object"' "$output_file" >/dev/null 2>&1; then
    structured=$(jq -c . "$output_file")
  fi

  if ((rc != 0)); then
    error="optimizer call failed (rc=$rc)"
  elif [[ "$event_valid" != true ]]; then
    error="invalid or empty Codex JSON event stream"
  elif ((failure_events > 0)); then
    error="Codex emitted a failure event"
  elif ((tool_events > 0)); then
    error="Codex emitted a runtime tool event"
  elif [[ "$structured" == null ]]; then
    error="missing structured output object"
  fi

  jq -cn \
    --arg fixture_id "$(jq -r '.id' <<<"$fixture")" \
    --arg variant "$variant" --arg model "$MODEL" --arg effort "$effort" \
    --argjson structured_output "$structured" \
    --argjson duration_ms "$duration_ms" --argjson exit_code "$rc" \
    --argjson event_stream_valid "$event_valid" \
    --argjson tool_event_count "$tool_events" \
    --argjson failure_event_count "$failure_events" \
    --argjson usage "$usage" --arg error "$error" '
    {fixture_id:$fixture_id, variant:$variant, model:$model, effort:$effort,
     structured_output:$structured_output, duration_ms:$duration_ms,
     exit_code:$exit_code, event_stream_valid:$event_stream_valid,
     tool_event_count:$tool_event_count, failure_event_count:$failure_event_count,
     usage:$usage, error:(if $error == "" then null else $error end)}' >"$result_file"
  return 0
}

SELECTED_IDS=$(printf '%s\n' "${ROWS[@]}" | jq -cs 'map(.id)')
VARIANTS_JSON=$(printf '%s\n' "${CHOSEN[@]}" | jq -Rsc 'split("\n")[:-1]')
CODEX_VERSION=$($CODEX_BIN --version 2>/dev/null || printf 'unknown')
SOURCE_REVISION=$(git -C "$ROOT" rev-parse --verify HEAD 2>/dev/null || true)
SOURCE_DIRTY=false
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal 2>/dev/null)" ]] || SOURCE_DIRTY=true
INSTRUCTION_SHA256=$(sha256sum "$INSTRUCTION" | awk '{print $1}')
SCHEMA_SHA256=$(sha256sum "$SCHEMA" | awk '{print $1}')
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n --arg generated_at "$GENERATED_AT" --arg model "$MODEL" \
  --arg codex_version "$CODEX_VERSION" --arg source_revision "$SOURCE_REVISION" \
  --argjson source_dirty "$SOURCE_DIRTY" --arg instruction_sha256 "$INSTRUCTION_SHA256" \
  --arg schema_sha256 "$SCHEMA_SHA256" --argjson smoke "$SMOKE" \
  --argjson fixture_ids "$SELECTED_IDS" --argjson variants "$VARIANTS_JSON" \
  --argjson jobs "$JOBS" --argjson timeout_seconds "$CALL_TIMEOUT" \
  --argjson command_template "$COMMAND_JSON" '{
    runner:"harness/run-codex.sh", runner_version:2, generated_at:$generated_at,
    model:$model, codex_version:$codex_version,
    source_revision:(if $source_revision == "" then null else $source_revision end),
    source_dirty:$source_dirty,
    instruction_sha256:$instruction_sha256, schema_sha256:$schema_sha256,
    smoke:($smoke == 1), fixture_ids:$fixture_ids, variants:$variants,
    jobs:$jobs, timeout_seconds:$timeout_seconds, command_template:$command_template
  }' >"$RUN_DIR/manifest.json"

active=0
for row in "${ROWS[@]}"; do
  fixture_id=$(jq -r '.id' <<<"$row")
  [[ "$fixture_id" =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe fixture id: $fixture_id"
  for variant in "${CHOSEN[@]}"; do
    effort=$(variant_effort "$variant")
    run_one "$row" "$variant" "$effort" \
      "$RUN_DIR/$variant/$fixture_id" "$WORK_ROOT/$variant/$fixture_id" &
    active=$((active + 1))
    if ((active >= JOBS)); then
      wait -n
      active=$((active - 1))
    fi
  done
done
wait

RESULTS=$RUN_DIR/results.jsonl
: >"$RESULTS"
for row in "${ROWS[@]}"; do
  fixture_id=$(jq -r '.id' <<<"$row")
  for variant in "${CHOSEN[@]}"; do
    result_file=$RUN_DIR/$variant/$fixture_id/result.json
    [[ -s "$result_file" ]] || die "call did not produce a result: $variant/$fixture_id"
    jq -c . "$result_file" >>"$RESULTS"
  done
done

jq -n --argjson vs "$VARIANTS_JSON" --slurpfile manifest "$RUN_DIR/manifest.json" \
  --slurpfile fixtures "$FIXTURES" --slurpfile results "$RESULTS" '
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
    | select(any(($s.speech_acts // [])[]?; (.normalized // "" | ascii_downcase) as $t
        | any($e.value[]; . as $stem | $t | contains($stem))))
    | $e.key] | unique | sort;
  def valid($s): ($s | type) == "object" and
    (($s | keys | sort) == (["assumptions","disposition","explicit_requirements",
      "optimized_prompt","rewrite_warrant","speech_acts"] | sort)) and
    ($s.disposition == "rewrite" or $s.disposition == "pass_through") and
    ($s.rewrite_warrant | IN("referent_bound","self_correction_discarded",
      "buried_constraint_hoisted","dictation_cleanup","ambiguity_restructured","none")) and
    (($s.speech_acts | type) == "array" and all($s.speech_acts[];
      type == "object" and ((keys | sort) == ["normalized","source_quote"]) and
      (.source_quote | type) == "string" and (.source_quote | length) > 0 and
      (.normalized | type) == "string")) and
    (($s.explicit_requirements | type) == "array" and all($s.explicit_requirements[];
      type == "object" and ((keys | sort) == ["normalized","source_quote"]) and
      (.source_quote | type) == "string" and (.source_quote | length) > 0 and
      (.normalized | type) == "string")) and
    (($s.assumptions | type) == "array" and all($s.assumptions[];
      type == "object" and ((keys | sort) == ["confidence","text"]) and
      (.text | type) == "string" and (.confidence | type) == "number" and
      .confidence >= 0 and .confidence <= 1)) and
    (($s.optimized_prompt | type) == "string") and
    (if $s.disposition == "pass_through"
     then $s.rewrite_warrant == "none"
     else $s.rewrite_warrant != "none" end);
  def provenance($s; $raw): valid($s) and
    all(($s.speech_acts + $s.explicit_requirements)[];
      .source_quote as $quote
      | ($quote | length) > 0 and ($raw | contains($quote)));
  def gate_core($s; $raw): provenance($s;$raw) and
    (if $s.disposition == "pass_through"
     then $s.optimized_prompt == $raw
     else ($s.optimized_prompt | length) > 0 and
       ($s.optimized_prompt | length) <= ([9000, (2 * ($raw | length) + 1500)] | min)
     end);
  def rate($n; $d): if $d == 0 then null else (($n / $d * 10000) | round) / 10000 end;
  def median($a): ($a | length) as $n
    | if $n == 0 then null
      elif ($n % 2) == 1 then $a[($n / 2 | floor)]
      else (($a[($n / 2 - 1)] + $a[($n / 2)]) / 2)
      end;
  def metric($n; $d): {count:$n,total:$d,rate:rate($n;$d)};
  def delta($a; $b): if ($a | type) == "number" and ($b | type) == "number"
    then (($a - $b) * 10000 | round) / 10000 else null end;
  ($fixtures[0] | map({key:.id,value:.}) | from_entries) as $fixture_map
  | [$vs[] as $variant
    | [$results[] | select(.variant == $variant)
       | . as $result
       | $fixture_map[$result.fixture_id] as $fixture
       | $result + {fixture:$fixture, schema_ok:valid($result.structured_output),
           provenance_ok:provenance($result.structured_output;$fixture.prompt),
           gate_core_ok:gate_core($result.structured_output;$fixture.prompt),
           got_acts:acts($result.structured_output)}] as $rows
    | [$rows[] as $row | $row.fixture.must_preserve[]? as $needle
       | select((($row.structured_output.optimized_prompt // "") | contains($needle)) or
         any((($row.structured_output.speech_acts // []) +
              ($row.structured_output.explicit_requirements // []))[]?;
           (.source_quote // "") | contains($needle)))] as $preserved
    | [$rows[].fixture.must_preserve[]?] as $preserve_total
    | [$rows[] as $row | $row.fixture.must_not_add[]? as $needle
       | select(($row.structured_output.optimized_prompt // "") | contains($needle))] as $added
    | ($rows | map(.fixture.pair_id) | map(select(. != null)) | unique) as $pair_ids
    | [$pair_ids[] as $pair_id
       | [$rows[] | select(.fixture.pair_id == $pair_id)]
       | select(length == 2)] as $pairs
    | [$pairs[] | select(
        (.[0].fixture.expected_speech_acts | unique | sort) !=
          (.[1].fixture.expected_speech_acts | unique | sort) and
        all(.[]; .schema_ok and
          .got_acts == (.fixture.expected_speech_acts | unique | sort)))] as $good_pairs
    | ($rows | map(.duration_ms | select(type == "number")) | sort) as $times
    | {variant:$variant, model:($rows[0].model // $manifest[0].model),
       effort:($rows[0].effort // ($variant | sub("^sol-";""))),
       calls:($rows | length),
       successful:metric(($rows | map(select(.error == null)) | length); $rows | length),
       schema_valid:metric(($rows | map(select(.schema_ok)) | length); $rows | length),
       source_quotes_valid:metric(($rows | map(select(.provenance_ok)) | length); $rows | length),
       hook_core_gate_valid:metric(($rows | map(select(.gate_core_ok)) | length); $rows | length),
       disposition_correct:metric(($rows | map(select(.schema_ok and
         .structured_output.disposition == .fixture.expected_disposition)) | length); $rows | length),
       speech_act_exact:metric(($rows | map(select(.schema_ok and
         .got_acts == (.fixture.expected_speech_acts | unique | sort))) | length); $rows | length),
       must_preserve:metric(($preserved | length); $preserve_total | length),
       must_not_add:{violations:($added | length), total:([$rows[].fixture.must_not_add[]?] | length)},
       no_runtime_tools:metric(($rows | map(select((.tool_event_count // 0) == 0)) | length); $rows | length),
       metamorphic_pairs:metric(($good_pairs | length); $pairs | length),
       latency_ms:{min:($times | min // null), median:median($times),
         max:($times | max // null)},
       tokens:{input:([$rows[].usage.input_tokens // 0] | add // 0),
         cached_input:([$rows[].usage.cached_input_tokens // 0] | add // 0),
         output:([$rows[].usage.output_tokens // 0] | add // 0)},
       errors:[$rows[] | select(.error != null) | {fixture_id,error,exit_code,
         tool_event_count,failure_event_count}]}
  ] as $stats
  | ($stats | map({key:.effort,value:.}) | from_entries) as $by_effort
  | {format_version:2, manifest:$manifest[0], variants:$stats,
     comparison:{medium_minus_low:{
       successful_rate:delta($by_effort.medium.successful.rate;$by_effort.low.successful.rate),
       schema_valid_rate:delta($by_effort.medium.schema_valid.rate;$by_effort.low.schema_valid.rate),
       source_quotes_valid_rate:delta($by_effort.medium.source_quotes_valid.rate;$by_effort.low.source_quotes_valid.rate),
       hook_core_gate_valid_rate:delta($by_effort.medium.hook_core_gate_valid.rate;$by_effort.low.hook_core_gate_valid.rate),
       disposition_correct_rate:delta($by_effort.medium.disposition_correct.rate;$by_effort.low.disposition_correct.rate),
       speech_act_exact_rate:delta($by_effort.medium.speech_act_exact.rate;$by_effort.low.speech_act_exact.rate),
       must_preserve_rate:delta($by_effort.medium.must_preserve.rate;$by_effort.low.must_preserve.rate),
       no_runtime_tools_rate:delta($by_effort.medium.no_runtime_tools.rate;$by_effort.low.no_runtime_tools.rate),
       median_latency_ms:delta($by_effort.medium.latency_ms.median;$by_effort.low.latency_ms.median)}}}
' >"$RUN_DIR/summary.json"

jq -r '
  def pct($x): if $x == null then "n/a" else ((($x * 1000) | round) / 10 | tostring) + "%" end;
  def cell($variant; $path): (.variants[] | select(.variant == $variant) | getpath($path)) // null;
  def row($name; $path; $kind):
    "| " + $name + " | " +
    ([.manifest.variants[] as $variant
      | cell($variant;$path)
      | if $kind == "rate" then pct(.) else (. // "n/a" | tostring) end] | join(" | ")) + " |";
  "# GPT-5.6 Sol CyberPrompt evaluation\n\n" +
  "- Generated: `" + .manifest.generated_at + "`\n" +
  "- Codex: `" + .manifest.codex_version + "`\n" +
  "- Fixtures: " + (.manifest.fixture_ids | length | tostring) +
    (if .manifest.smoke then " (smoke set)" else "" end) + "\n\n" +
  "| Metric | " + (.manifest.variants | join(" | ")) + " |\n" +
  "|---|" + ([.manifest.variants[] | "---"] | join("|")) + "|\n" +
  row("Successful calls";["successful","rate"];"rate") + "\n" +
  row("Schema valid";["schema_valid","rate"];"rate") + "\n" +
  row("Source quotes valid";["source_quotes_valid","rate"];"rate") + "\n" +
  row("Hook core gate valid";["hook_core_gate_valid","rate"];"rate") + "\n" +
  row("Disposition accuracy";["disposition_correct","rate"];"rate") + "\n" +
  row("Speech-act exact match";["speech_act_exact","rate"];"rate") + "\n" +
  row("Must-preserve recall";["must_preserve","rate"];"rate") + "\n" +
  row("Must-not-add violations";["must_not_add","violations"];"number") + "\n" +
  row("No runtime tools";["no_runtime_tools","rate"];"rate") + "\n" +
  row("Metamorphic pair integrity";["metamorphic_pairs","rate"];"rate") + "\n" +
  row("Minimum duration (ms)";["latency_ms","min"];"number") + "\n" +
  row("Median duration (ms)";["latency_ms","median"];"number") + "\n" +
  row("Maximum duration (ms)";["latency_ms","max"];"number")
' "$RUN_DIR/summary.json" >"$RUN_DIR/summary.md"

printf 'Codex evaluation complete: %s\n' "$RUN_DIR"
printf 'Machine summary: %s\n' "$RUN_DIR/summary.json"
printf 'Human summary: %s\n' "$RUN_DIR/summary.md"
