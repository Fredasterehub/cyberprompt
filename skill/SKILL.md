---
name: cyberprompt
description: Toggle and manage the automatic cyberprompt hook that rewrites the operator's prompts via the claude-5 skill before the session model acts on them. Trigger when the user says "optimizer on/off", "active/désactive l'optimiseur", "toggle prompt optimizer", asks for the optimizer's status, wants to change which model runs the optimization, wants to see the original vs optimized prompt log, wants to install the optimizer for their user, or reports the optimizer misbehaving. Do NOT trigger for general prompting advice (that's the claude-5 skill) or for writing new hooks.
---

# Prompt Optimizer — toggle & management

A `UserPromptSubmit` hook that intercepts every operator prompt, rewrites it
with a non-agentic headless `claude -p` call (--safe-mode, no tools/MCP, 60 s
timeout, JSON-schema output) armed with the claude-5 skill references
(`~/.claude/skills/claude-5/`), and injects it as an ADVISORY contract in
`additionalContext`: the original prompt stays authoritative; the rewrite
(explicit task / constraints traceable to the original / non-binding
inferences / execution brief) is an execution aid. Deterministic gates reject
bad rewrites (schema validation, source-quote substring check, length ceiling)
and a `pass_through` disposition skips injection when the prompt is already
clear. The operator sees the rewrite via `systemMessage`; every pair is logged
with disposition/duration/gate_failure.

State directory: `~/.claude/cyberprompt/`

| File | Role |
|------|------|
| `enabled` | Sentinel — exists = hook active. No restart needed either way. |
| `config` | `MODEL=`, `EFFORT=` (pinned reasoning effort, default high), `MIN_CHARS=`, optional `CLAUDE5_SKILL=` override |
| `instruction.txt` | Optimizer system instruction template |
| `log.jsonl` | Audit trail: `{ts, session, optimizer_model, target_model, original, optimized}` |
| `error.log` | stderr of failed `claude -p` calls |

## Install (first time for a user)

Run `bash ~/.claude/skills/cyberprompt/install.sh` — copies the hook to
`~/.claude/hooks/`, seeds the state dir, and registers the hook in
`~/.claude/settings.json` (idempotent, never overwrites an existing config).
Requires `jq` and the claude-5 skill at `~/.claude/skills/claude-5` (or set
`CLAUDE5_SKILL=` in the config).

## Commands (execute directly with Bash)

- **on** — `touch ~/.claude/cyberprompt/enabled` then confirm.
- **off** — `rm -f ~/.claude/cyberprompt/enabled` then confirm.
- **status** — report: sentinel present?, current `MODEL`/`MIN_CHARS`, number of
  log entries, last entry timestamp, any recent `error.log` content.
- **model X** — edit `MODEL=` in `config`. Valid: `claude-opus-5` (default,
  benchmarked best), `claude-fable-5`, `claude-sonnet-5`.
- **effort X** — edit `EFFORT=` in `config` (low|medium|high|xhigh|max;
  default high, passed explicitly via `--effort` so the session's effortLevel
  never silently changes the optimizer).
- **lore / level / xp** — WORDRUNNER.EXE persona (netrunner alignment): the
  systemMessage header shows level + XP (1 log entry = 1 XP; thresholds
  50/125/250/500/1000/2000/4000). Backstory in `LORE.md` next to this file —
  read it aloud on request.
- **log [n]** — show the last n pairs:
  `tail -n 5 ~/.claude/cyberprompt/log.jsonl | jq -r '"[\(.ts)] \(.optimizer_model)→\(.target_model)\nORIGINAL: \(.original)\nOPTIMIZED: \(.optimized)\n"'`

## Behavior notes

- **Fail-open**: any failure (skill missing, `claude -p` error/timeout/empty
  output) passes the original prompt through unchanged and warns the operator
  via `systemMessage`.
- **Skipped automatically**: slash commands (`/...`), shell (`!`) and memory
  (`#`) shortcuts, prompts under `MIN_CHARS`, and all subagent prompts
  (`agent_id` present). Recursion into the hook's own `claude -p` call is
  guarded by the `PROMPT_OPTIMIZER_BUSY` env var.
- The target model is auto-detected from the session transcript (last assistant
  message), so the rewrite uses the matching per-model reference file.
- Platform constraint: `UserPromptSubmit` cannot truly replace the prompt — the
  model still sees the original, plus a system-reminder instructing it to act
  on the optimized version. This is the closest achievable to substitution.
