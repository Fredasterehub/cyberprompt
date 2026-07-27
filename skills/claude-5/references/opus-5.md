# Prompting Claude Opus 5

Distilled from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5 and https://platform.claude.com/docs/en/build-with-claude/effort (captured 2026-07-26). Snippets in ```text blocks are official, copy-paste-ready prompt language.

## Profile

Built for complex agentic coding and enterprise work; strongest on multi-file features, large refactors, end-to-end feature work, and long-horizon agentic tasks. Completes full tasks rather than leaving stubs, and performs best given the complete task specification up front and left to run. High-precision, high-recall code review that holds at lower effort. 1M-token context window (default and maximum) with consistent behavior throughout. Coordinates subagent teams well (writer–verifier patterns). Runs existing Opus 4.8 prompts well out of the box.

API notes: thinking is on by default; disabling thinking is only possible at effort `high` or below (`xhigh`/`max` with `thinking: disabled` returns 400).

## Effort

Start with `high` (the default) and adjust on evals: step up to `xhigh` for demanding coding/agentic work, `max` only when unconstrained spending is justified. Use `low` and `medium` **liberally** as the primary control for cost and response time wherever quality holds — efficiency at lower effort is a headline improvement. Re-run an effort sweep when migrating; don't carry old defaults. At `xhigh`/`max`, set a large `max_tokens` (64k starting point).

Effort controls thinking volume, **not** visible response length — prompt for length explicitly (below).

## Patterns

### Response length and verbosity

Default user-facing responses run longer than prior Opus models. Lowering effort won't reliably shorten them; prompt instead:

```text
Keep responses focused, brief, and concise. Keep disclaimers and caveats short, and spend most of the response on the main answer. When asked to explain something, give a high-level summary unless an in-depth explanation is specifically requested.
```

In a long system prompt, add a short reminder near the end:

```text
<tone_preference>
Keep outputs reasonably concise.
</tone_preference>
```

### User-facing progress updates

Opus 5 narrates readily during agentic work. Describe the cadence and shape you want; positive examples beat "don't" lists:

```text
Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.
```

### Written deliverable length

Files it writes (reports, docs, summaries) also run long:

```text
Match the length of written documents to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate.
```

### Over-verification — REMOVE verification instructions

Opus 5 verifies its own work unprompted. Explicit verification instructions ("include a final verification step," "use a subagent to verify," "double-check your answer") cause over-verification: wasted tokens, no quality gain. Strip them from migrated prompts and legacy harness scaffolding. The same goes for re-check instructions — it self-corrects well without them.

### Task scope containment

Opus 5 can expand scope, adding steps that weren't requested. For narrow tasks:

```text
Deliver what was asked, at the scope intended. Make routine judgment calls yourself, and check in only when different readings of the request would lead to materially different work. If the request seems mistaken or a better approach exists, say so in a sentence and continue with the task as asked rather than quietly narrowing, widening, or transforming it. Finish the whole task, and stop short of actions that are clearly beyond what was asked.
```

### Subagent damping

Opus 5 delegates readily; that pays on genuinely independent sizeable tracks but multiplies cost on small tasks. Give explicit delegation criteria or deterministic caps:

```text
Delegate to a subagent only for large tasks that are genuinely independent and parallelizable, such as a wide multi-file investigation. Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work. If one subagent can complete the task, use one rather than several, and keep spawn counts low.
```

### Correction narration

It narrates self-corrections more than prior models. To limit that to corrections that matter:

```text
Only correct an earlier statement when the error would change the user's code, conclusions, or decisions. State corrections plainly and briefly, then continue the task. For slips that change nothing for the user, make the fix and move on without noting it.
```

### Code review prompts

High recall per pass, mostly-real findings. If the prompt says "only report high-severity issues" or "be conservative," it complies literally and reports less. Ask for everything; filter downstream. (Full recommended review language is in `sonnet-5.md` — it applies to both models.)

### Running with thinking disabled

Prefer thinking on at lower effort over thinking off — better quality at similar cost. If thinking must stay off, two artifacts can appear: tool calls written as text (never executed, pollutes agentic history) and internal XML tags leaking into output. Remove any "do not think/reason" rule (it increases tag leakage; naming thinking tags explicitly is less effective than the general form), and add:

```text
When you use a tool, you may say a brief sentence first. If no tool can express what the user asked for, say so instead of guessing. Do not include internal or system XML tags in your response.
```

### Vision

Strong on charts, documents, diagrams, and UI replication. Re-validate old prompt-side vision workarounds — likely no longer needed. Give it tools to iteratively analyze, crop, and visually verify: tool use is a more cost-effective lever than thinking alone.
