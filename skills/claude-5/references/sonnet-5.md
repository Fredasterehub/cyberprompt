# Prompting Claude Sonnet 5

Distilled from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5 and https://platform.claude.com/docs/en/build-with-claude/effort (captured 2026-07-26). Snippets in ```text blocks are official, copy-paste-ready prompt language.

## Profile

Strong in coding and agentic tasks; runs existing Sonnet 4.6 prompts well out of the box. More agentic than 4.6 by default — reaches for tools and self-verification loops readily. Calibrates response length to task complexity. The workhorse for standard pipelines, high-volume, and cost-sensitive work.

API notes: adaptive thinking is ON by default (a change from 4.6 — requests without a `thinking` field now think). Disable entirely with `thinking: {type: "disabled"}`. Manual extended thinking (`budget_tokens`) returns 400. Sampling parameters (`temperature`, `top_p`, `top_k`) return 400 — steer style through the prompt. New tokenizer produces ~30% more tokens for the same text: revisit `max_tokens` limits tuned for 4.6, and leave headroom at `high`+ effort or you'll get thinking-heavy truncated responses with `stop_reason: "max_tokens"`.

## Effort — the primary lever

Defaults to `high`. Recommended ladder:

- `max` — absolute maximum capability, unconstrained token spend.
- `xhigh` — the hardest coding and agentic use cases.
- `high` — default; balances token usage and intelligence for most use cases.
- `medium` — cost-sensitive step-down. Comparable intelligence to Sonnet 4.6 at `high`.
- `low` — short, scoped, latency-sensitive tasks that are not intelligence-sensitive.

Sonnet 5 respects effort **strictly**, especially at the low end: at `low`/`medium` it scopes work to exactly what was asked. If you see shallow reasoning on complex problems, raise effort rather than prompting around it. If effort must stay `low` for latency, add targeted guidance:

```text
This task involves multistep reasoning. Think carefully through the problem before responding.
```

If it thinks more often than you'd like (can happen with large system prompts), steer the trigger:

```text
Thinking adds latency and should only be used when it will meaningfully improve answer quality, typically for problems that require multistep reasoning. When in doubt, respond directly.
```

## Patterns

### Literal instruction following

Sonnet 5 interprets prompts literally and explicitly, particularly at lower effort. It does not silently generalize an instruction from one item to another and does not infer requests you didn't make. This precision is ideal for tuned API pipelines and structured extraction — but you must state scope explicitly: "Apply this formatting to every section, not just the first one."

### Verbosity

Length auto-calibrates to task complexity. To trim:

```text
Provide concise, focused responses. Skip non-essential context, and keep examples minimal.
```

Positive examples of the concision you want beat negative instructions.

### Tool use triggering

More tool-happy than 4.6 at `high`/`xhigh`; with thinking disabled it reaches for tools less — add an explicit nudge if you rely on tool calls with thinking off. If a specific tool undertriggers, describe clearly why and when to use it.

### Progress updates

Provides regular, higher-quality updates on long agentic traces by itself. Remove legacy scaffolding like "after every 3 tool calls, summarize progress" — describe the desired update shape only if the default doesn't fit.

### Tone and style

Re-evaluate voice prompts against the new baseline; steer with instructions, not sampling parameters (they 400 now):

```text
Use a warm, collaborative tone. Acknowledge the user's framing before answering.
```

### Design and frontend defaults

Settles into a consistent default visual style on open-ended briefs. Generic negations ("don't use that color") just shift it to another fixed palette. Two reliable approaches:

1. **Specify a concrete alternative** — it follows explicit specs precisely (palette hexes, typography, spacing, radii, motion).
2. **Have it propose options first** — "Before building, propose 4 distinct visual directions tailored to this brief (each as: bg hex / accent hex / typeface, plus a one-line rationale). Ask the user to pick one, then implement only that direction." With `temperature` gone, this is the recommended way to get variety across runs.

Anti-"AI-slop" system snippet (fuller treatment in the official frontend-design skill):

```text
<frontend_aesthetics>
NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white or dark backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character. Use unique fonts, cohesive colors and themes, and animations for effects and micro-interactions.
</frontend_aesthetics>
```

### Interactive coding products

Specify task, intent, and constraints upfront in the first turn — well-specified single-turn prompts maximize autonomy and token efficiency; drip-fed ambiguity degrades both. Use `xhigh`/`high` effort, add autonomous modes, minimize required user interactions.

### Code review harnesses

If recall looks lower than an older model, it's likely the harness: Sonnet 5 follows "only report high-severity / be conservative / don't nitpick" faithfully — same investigation depth, fewer reported findings. Recommended language:

```text
Report every issue you find, including ones you are uncertain about or consider low-severity. Do not filter for importance or confidence at this stage - a separate verification step will do that. Your goal here is coverage: it is better to surface a finding that later gets filtered out than to silently drop a real bug. For each finding, include your confidence level and an estimated severity so a downstream filter can rank them.
```

If you do want single-pass self-filtering, define the bar concretely: "report any bugs that could cause incorrect behavior, a test failure, or a misleading result; only omit nits like pure style or naming preferences."

### Computer use

Supports `computer_20251124`, up to 2576px / 3.75MP. 1080p images balance performance and cost; 720p or 1366×768 for cost-sensitive workloads.
