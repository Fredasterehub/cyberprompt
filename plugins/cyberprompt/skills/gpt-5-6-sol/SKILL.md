---
name: gpt-5-6-sol
description: Research, write, review, migrate, and deploy prompts, skills, agents, hooks, tool descriptions, and workflows for GPT-5.6 Sol. Use whenever Codex needs current GPT-5.6 Sol prompting guidance, needs to compose a prompt that Sol will execute, chooses Sol reasoning effort, optimizes a Codex CLI workflow, migrates an older GPT prompt stack, or must pair prompt advice with fresh official documentation, primary-source best practices, state-of-the-art implementation evidence, and a concrete deployment example. Refresh sources on every use; do not use this skill for Claude-targeted prompts.
---

# GPT-5.6 Sol

Build lean, evidence-backed prompt contracts for `gpt-5.6-sol`. Treat the model as capable: define the outcome, hard constraints, evidence, autonomy boundary, completion bar, and output contract, then leave routine path selection to Sol.

## Freshness gate

Complete this gate on every invocation before drafting or revising the prompt.

1. Fetch the current official GPT-5.6 model guide and Sol prompting guide through the OpenAI Docs tools. Use official OpenAI web pages only if the docs tools are unavailable or incomplete.
2. When the execution surface is Codex, inspect the installed `codex --version` and the relevant `--help` or config schema. Product behavior can move faster than a bundled reference.
3. Search the task domain for current primary sources: official framework or platform documentation, standards, release notes, maintainers' repositories, and original research papers. Prefer deployed reference implementations over commentary about them.
4. Establish an explicit `as of YYYY-MM-DD` date. Current work must cover evidence available through July 31, 2026 or later.
5. Never say that browsing changed or refreshed the model's training data. Say that it refreshed the working context. If fresh retrieval is unavailable, label the bundled snapshot as an offline fallback and do not claim current or state-of-the-art coverage.

Use [references/sources.md](references/sources.md) for canonical starting URLs and fallback rules. Read [references/prompting.md](references/prompting.md) when composing or migrating a prompt. Read [references/deployment.md](references/deployment.md) when the user needs Codex, API, hook, plugin, or production wiring.

## Workflow

1. Establish the execution frame: target model, reasoning effort, task, prompt layer, available tools, authorization boundary, output artifact, and acceptance criteria.
2. Inventory the existing prompt stack before migrating it. Preserve user-visible behavior, explicit values, schemas, tool semantics, and downstream parsers.
3. Remove repeated rules, obsolete scaffolding, irrelevant examples, generic anti-laziness pressure, and contradictions. State each surviving instruction once.
4. Compose outcome-first. Include only context and constraints that change behavior. Use decision rules for judgment calls and absolutes only for true invariants.
5. Define stopping conditions, required evidence, failure behavior, and the smallest missing fact that should trigger a question.
6. Add a concrete invocation or deployment example using the verified current surface. Do not invent flags, fields, limits, prices, or capabilities.
7. Validate with representative cases. Compare the existing prompt first; change one instruction group at a time so regressions remain attributable.

## Sol calibration

- Start at `low` for bounded, latency-sensitive transformations and at `medium` for general agentic work. Compare both on real cases before choosing a product default.
- Use `high`, `xhigh`, `max`, or Codex-specific higher settings only when evaluation shows a meaningful quality gain. Do not encode “think harder” rituals in the prompt.
- Keep prompts lean. Sol usually does not need prescribed reasoning steps, repeated tool mandates, or generic verification prose.
- Preserve user-provided values exactly. For implicit choices, provide criteria instead of hard-coded guesses.
- Keep autonomy policy compact: distinguish research/review from implementation and local reversible work from external, destructive, costly, or scope-expanding action.
- Specify validation that matters to the artifact. Do not add tests, searches, citations, or process steps when the user did not authorize them and the host policy does not require them.
- For long workflows, request a short preamble and sparse milestone updates, not narration of routine tool calls.

## Deliverable

Return the requested prompt or implementation first. Include, as applicable:

- target surface and reasoning setting;
- the final prompt or scoped patch;
- one concrete deployment or invocation example;
- validation or evaluation cases;
- an `as of` date and citations for current claims;
- bounded gaps when current evidence or runtime access is unavailable.

Keep source discussion proportional to the task, but never omit the freshness date or evidence behind current model/runtime claims.
