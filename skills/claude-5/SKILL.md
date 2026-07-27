---
name: claude-5
description: Write, review, and migrate prompts for the Claude 5 model family — Fable 5, Opus 5, and Sonnet 5. Make sure to use this skill whenever you are about to write ANY prompt that a Claude model will execute (subagent and Agent-tool prompts, Workflow agent() prompts, .claude/agents definitions, system prompts, skill bodies, claude -p invocations, Messages API requests), whenever choosing which model or effort level fits a task, and whenever a prompt written for an earlier Claude model needs updating. The three models fail differently — instructions that help one degrade another — so never write model-targeted prompts from memory alone.
---

# Claude 5 Prompting

Compose prompts calibrated to the specific Claude 5 model that will execute them. The three models have distinct behavioral profiles, and the most common prompting mistakes are habits carried over from earlier model generations: instructions the new models follow too literally, verification rituals they already perform on their own, and API parameters that now return errors.

Everything here is distilled from official Anthropic documentation captured on 2026-07-26. Sources and the refresh procedure are at the bottom.

## Workflow

1. **Identify the frame.** Establish four things before writing a word: target model, effort level, the task itself, and the execution surface (Messages API call, Claude Code subagent or agent definition, Workflow `agent()` prompt, system prompt, `claude -p`). If the model or effort is not specified, choose them with the selection table below and state your reasoning.

2. **Read the target model's reference file before writing.** One file per model the prompt targets:
   - `references/fable-5.md` — Fable 5 / Mythos 5: long-horizon autonomy, progress grounding, refusal-sensitive patterns
   - `references/opus-5.md` — Opus 5: verbosity control, over-verification, subagent damping
   - `references/sonnet-5.md` — Sonnet 5: strict effort respect, literal instruction following, adaptive thinking

   Additionally read `references/shared.md` when composing a full system prompt from scratch, migrating a prompt from an older Claude model, or building long-context or agentic scaffolding. When the question is how to *run* a model rather than what to write — wiring subagents, workflows, agent files, CLI, or API calls — read `references/invocation.md` for the verified per-surface model and effort controls.

   Do not skip the read because the patterns feel familiar — half of them are counter-intuitive reversals of pre-2026 prompting habits (for example, telling Opus 5 to double-check its work makes it slower and no better).

3. **Compose.** Apply the model's patterns. Give the reason behind each constraint so the model can generalize — an explained instruction beats an all-caps MUST. Include only instructions that change *this* model's behavior: instructions describing what the model already does by default waste tokens and can invert into pathologies (over-verification, over-triggering, over-thinking).

4. **Pre-flight check.** Run the checklist below before delivering the prompt. If the prompt is for the API, check the request parameters too, not just the prompt text.

## Model and effort selection

| Task profile | Model | Effort |
|---|---|---|
| Hardest problems: multiday autonomous runs, ambiguous scope, first-shot complex systems, dense vision | Fable 5 | `high` default; `xhigh` for capability-sensitive work; `medium`/`low` still strong for routine steps |
| Difficult agentic coding: multi-file features, large refactors, code review, 1M-token context | Opus 5 | `high` default; `xhigh` for demanding runs; use `low`/`medium` liberally where quality holds |
| Standard coding and agentic work, pipelines, extraction, high-volume or cost-sensitive steps | Sonnet 5 | `high` default; `xhigh` hardest tasks; `medium` cost step-down; `low` latency-bound only |

Principles behind the table:

- Effort — not switching models — is the primary cost/latency lever within a task. Set it explicitly via `output_config: {effort: "..."}` (API) or the `effort` field/flag (Claude Code).
- Cross-generation calibration: Sonnet 5 at `medium` ≈ Sonnet 4.6 at `high`; lower-effort Fable 5 often exceeds `xhigh` on prior models. Re-sweep effort on your own evals when migrating; don't carry old settings.
- Hold effort constant within a conversation that relies on prompt caching — changing it invalidates cached prefixes.
- Fable 5 is not for offensive cybersecurity or biology/life-sciences work: safety classifiers can return `stop_reason: "refusal"`. Route those domains (and benign work that risks tripping them) to Opus with a fallback configured.

## Pre-flight checklist — all Claude 5 models

API-breaking (returns 400 or is silently dead):
- No `temperature`, `top_p`, or `top_k` — steer tone and variety through the prompt instead.
- No `budget_tokens` / manual extended thinking — adaptive thinking plus `effort` replaced it.
- No prefilled final assistant message — use structured outputs, explicit format instructions, or post-processing.
- Leave `max_tokens` headroom at high efforts: it caps thinking plus response combined.

Behavioral inversions vs. older models — remove these on sight:
- "Double-check / verify your work" aimed at Opus 5 → causes over-verification; it already self-verifies.
- "Echo / transcribe / explain your internal reasoning" aimed at Fable 5 → triggers `reasoning_extraction` refusals; read thinking blocks instead.
- "CRITICAL: you MUST use this tool" anti-laziness pressure → Claude 5 models over-trigger; use plain "Use this tool when...".
- "Only report high-severity issues / be conservative" in review prompts → suppresses recall; ask for full coverage and filter in a separate pass.
- Vague scope on Sonnet 5 → it is literal and won't generalize beyond what you wrote; state scope explicitly ("apply to every section, not just the first").

## Freshness

Captured 2026-07-26 from official Anthropic docs:

- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- https://platform.claude.com/docs/en/build-with-claude/effort

If a newer Claude generation exists, or observed behavior contradicts these notes, re-fetch the sources before trusting them — appending `.md` to any platform.claude.com/docs or code.claude.com/docs URL returns clean markdown — and update this skill's references with a new capture date.
