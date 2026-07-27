# Cross-model prompting techniques (all Claude 5 / current models)

Distilled from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices and https://platform.claude.com/docs/en/build-with-claude/effort (captured 2026-07-26). Read this when composing a full system prompt, migrating from an older model, or building agentic scaffolding.

## General principles

- **Clear and direct.** Treat the model as a brilliant new employee with no context on your norms. Golden rule: if a colleague with minimal context would be confused by the prompt, so will the model. If you want above-and-beyond behavior, request it explicitly ("Include as many relevant features as possible. Go beyond the basics.").
- **Give the why.** Context behind an instruction ("your response will be read aloud by TTS, so never use ellipses") outperforms the bare rule — the model generalizes from the reason.
- **Examples (3–5).** The most reliable formatting/tone lever. Make them relevant, diverse, and wrapped in `<example>` / `<examples>` tags.
- **XML structure.** Separate instructions, context, input, and examples with consistent, descriptive tags. Nest naturally (`<documents><document index="1">…`).
- **Role.** One system-prompt sentence focuses behavior: "You are a helpful coding assistant specializing in Python."
- **Long context (20k+ tokens).** Longform data at the TOP, query/instructions at the END (up to ~30% quality gain). Wrap documents in tags with `<source>` metadata. Ask for relevant quotes in `<quotes>` tags first to ground responses.
- **Model identity.** If the app must self-identify: "The assistant is Claude, created by Anthropic. The current model is [model]." For apps that pick model strings, state the exact string in the prompt.

## Output and formatting

- Tell it what TO do, not what to avoid: "Write in smoothly flowing prose paragraphs" beats "Don't use markdown."
- XML format indicators: "Write the prose sections in <smoothly_flowing_prose_paragraphs> tags."
- Prompt style leaks into output style — matching your prompt's formatting to the desired output helps.
- To suppress bullet-point/markdown overuse, use the official `<avoid_excessive_markdown_and_bullet_points>` block from the best-practices page; to suppress LaTeX, request plain-text math notation explicitly.
- **No prefills.** Prefilled final assistant messages return 400 on Claude 4.6+. Migrations: structured outputs for format constraints; "respond directly without preamble" for preamble removal; move continuations into the user message ("Your previous response was interrupted and ended with `[text]`. Continue."); hydrate context via user-turn injections or tools, not prefills.

## Tool use

- Be explicit for action: "Change this function" (acts) vs "Can you suggest changes" (suggests). Official toggles:

```text
<default_to_action>
By default, implement changes rather than only suggesting them. If the user's intent is unclear, infer the most useful likely action and proceed, using tools to discover any missing details instead of guessing. Try to infer the user's intent about whether a tool call (e.g., file edit or read) is intended or not, and act accordingly.
</default_to_action>
```

```text
<do_not_act_before_instructions>
Do not jump into implementation or change files unless clearly instructed to make changes. When the user's intent is ambiguous, default to providing information, doing research, and providing recommendations rather than taking action. Only proceed with edits, modifications, or implementations when the user explicitly requests them.
</do_not_act_before_instructions>
```

- Dial back aggressive triggering language ("CRITICAL: You MUST use this tool when...") — current models over-trigger on it; plain "Use this tool when..." suffices.
- Parallel tool calling is near-default; boost to ~100% with the official `<use_parallel_tool_calls>` block, or damp with "Execute operations sequentially with brief pauses between each step."

## Thinking

- Adaptive thinking (`thinking: {type: "adaptive"}`) is the current mechanism; the model decides when/how deeply to think, calibrated by `effort` and query complexity. On Fable 5 / Mythos 5 thinking is always on; on Opus 5 / Sonnet 5 it's on by default; on Opus 4.6–4.8 / Sonnet 4.6 it's off when omitted.
- `budget_tokens` is dead on 4.7+ (400 error). Migrate: `thinking: {type: "adaptive"}` + `output_config: {effort: ...}`.
- Prefer general instructions ("think thoroughly") over prescriptive step-by-step reasoning plans.
- Few-shot examples can include `<thinking>` tags to model the reasoning pattern.
- "Ask Claude to self-check" helps on most models — **except Opus 5**, where it causes over-verification (see opus-5.md).

## Agentic systems

- **State tracking:** structured formats (JSON like `tests.json`) for structured state; freeform notes (`progress.txt`) for progress; git for checkpoints and history; emphasize incremental progress.
- **Multi-context-window workflows:** first window sets the framework (tests, `init.sh` setup scripts); later windows iterate a todo list. Locked tests: "It is unacceptable to remove or edit tests because this could lead to missing or buggy functionality." Fresh-start beats compaction when state lives on disk — be prescriptive: "Review progress.txt, tests.json, and the git logs."
- **Context limits:** with a compacting harness, tell the model so it doesn't wrap up early (official snippet: "Your context window will be automatically compacted... Never artificially stop any task early regardless of the context remaining."). Encourage full use: "It's encouraged to spend your entire output context working on the task - just make sure you don't run out of context with significant uncommitted work."
- **Autonomy vs safety** — the official reversibility snippet:

```text
Consider the reversibility and potential impact of your actions. You are encouraged to take local, reversible actions like editing files or running tests, but for actions that are hard to reverse, affect shared systems, or could be destructive, ask the user before proceeding.

Examples of actions that warrant confirmation:
- Destructive operations: deleting files or branches, dropping database tables, rm -rf
- Hard to reverse operations: git push --force, git reset --hard, amending published commits
- Operations visible to others: pushing code, commenting on PRs/issues, sending messages, modifying shared infrastructure

When encountering obstacles, do not use destructive actions as a shortcut. For example, don't bypass safety checks (e.g. --no-verify) or discard unfamiliar files that may be in-progress work.
```

- **Subagent guidance** (when delegation overtriggers):

```text
Use subagents when tasks can run in parallel, require isolated context, or involve independent workstreams that don't need to share state. For simple tasks, sequential operations, single-file edits, or tasks where you need to maintain context across steps, work directly rather than delegating.
```

- **Anti-overengineering** — official scope/documentation/defensive-coding/abstractions block:

```text
Avoid over-engineering. Only make changes that are directly requested or clearly necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need extra configurability.

- Documentation: Don't add docstrings, comments, or type annotations to code you didn't change. Only add comments where the logic isn't self-evident.

- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs).

- Abstractions: Don't create helpers, utilities, or abstractions for one-time operations. Don't design for hypothetical future requirements. The right amount of complexity is the minimum needed for the current task.
```

- **General solutions over test-gaming:** the official "high-quality, general-purpose solution" block — implement real logic, no hardcoded test-passing, flag infeasible tasks or wrong tests instead of working around them.
- **Grounding:** the official `<investigate_before_answering>` block — never speculate about unopened code; read referenced files before answering.
- **Research tasks:** define success criteria; ask for competing hypotheses, confidence tracking, and a persisted hypothesis tree / research notes file.

## Effort (API mechanics)

- Request-level: `output_config: {effort: "low" | "medium" | "high" | "xhigh" | "max"}`. `high` = same as omitting. Affects ALL tokens: text, tool calls, thinking. Lower effort → fewer/combined tool calls, terser output; higher → more exploration, more verification.
- `xhigh`: Fable 5, Mythos 5, Opus 5, Opus 4.8/4.7, Sonnet 5 only. `adaptive` is NOT an effort value.
- Keep effort constant within cache-reliant conversations — changing it invalidates cached prefixes. Vary it across workloads, not within one.
- Set it explicitly in production; the right level depends on model and workload (see per-model files).

## Migration quick list (older Claude → Claude 5)

1. Remove `temperature`/`top_p`/`top_k` (400 on Sonnet 5+ and adaptive-thinking models).
2. Replace `budget_tokens` extended thinking with adaptive + effort.
3. Remove prefilled assistant turns; use structured outputs / instructions.
4. Strip verification/self-check rituals for Opus 5; strip forced-progress-summaries for Sonnet 5.
5. Dial back anti-laziness and "MUST use tool" pressure — over-triggering is the new failure mode.
6. Re-sweep effort levels on your evals; don't carry old settings (Sonnet 5 medium ≈ 4.6 high).
7. Be explicit about desired output detail ("go beyond the basics") — and about scope, for literal models.
