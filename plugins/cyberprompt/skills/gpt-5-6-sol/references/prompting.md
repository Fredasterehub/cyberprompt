# GPT-5.6 Sol prompting snapshot

Snapshot date: 2026-07-31. Fresh official docs override this file.

## Core pattern

Give Sol the destination and completion bar:

```text
Role: [function and operating context]
Goal: [user-visible outcome]
Success criteria: [observable completion conditions]
Constraints: [policy, evidence, compatibility, and side-effect limits]
Tools: [routing rules and prerequisites]
Output: [artifact, structure, length, and evidence]
Stop rules: [retry, fallback, question, abstention, and completion]
```

Keep each section short and omit sections that do not change behavior.

## High-value instructions

- State each rule once and remove contradictions.
- Preserve explicit user values; use decision criteria for implicit choices.
- Name retrieval prerequisites when action depends on evidence.
- Parallelize independent reads; keep dependent decisions sequential.
- Define what action the request authorizes and which actions require confirmation.
- Specify validation tied to the artifact: targeted tests, types, build, render, smoke check, schema validation, or citations.
- Give fallback and stopping conditions so tool loops end for the right reason.
- For edits, name what must be preserved before asking for improvements.

## Common regressions

- Broad “be concise” instructions can make Sol omit required substance; say what a short answer must retain.
- Repeated approval language can cause unnecessary pauses. Keep one compact autonomy policy.
- Universal keyword maps and defaults override context. Prefer criteria.
- Generic “use tools efficiently” does not route tools. Name the task stage, eligible tools, evidence, retry limit, and handoff.
- A full prompt rewrite hides the source of regressions. Change one instruction group and replay the same evaluations.

## Evaluation discipline

- Keep the original prompt as a baseline and use representative, adversarial, and metamorphic cases.
- Define narrow graders for the properties that matter; aggregate scores can hide intent loss on a critical slice.
- Separate prompt-search examples from held-out validation cases. Manually inspect changed behavior before promotion.
- Track quality, violations, latency, and cost together. A higher task score does not excuse a new authorization, safety, provenance, or compatibility regression.
- Treat optimizer and executor model/version as part of the artifact. Re-run the fixed suite when either changes.
- Reserve evolutionary or search-based optimizers such as GEPA or MIPROv2 for offline, evaluator-backed improvement. A per-turn rewrite should be bounded, reversible, source-traceable, and allowed to pass through.

## Effort

Codex CLI 0.146 reports Sol default effort `low`; the API guide describes `medium` as a balanced starting point when effort is omitted in API requests. Treat the execution surface as material. Benchmark the same prompt at the current setting and one adjacent setting. Reserve higher efforts for measured hard cases.
