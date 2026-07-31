---
name: cyberprompt
description: Install, enable, disable, configure, inspect, and troubleshoot CYBERPROMPT for Codex CLI, the GPT-5.6 Sol UserPromptSubmit optimizer bundled in this plugin. Use when the user says cyberprompt on/off, optimizer on/off, toggle cyberprompt, asks for status, logs, XP, lore, CYBERPROMPT's model or effort settings, wants the Codex installation or hook-trust steps, requests a one-prompt bypass, or reports a failed, slow, noisy, or inaccurate rewrite. Do not trigger for general Sol prompting advice; use cyberprompt:gpt-5-6-sol for that.
---

# CYBERPROMPT for Codex

Manage the per-prompt Codex forge. The plugin supplies a `UserPromptSubmit` hook; the sentinel controls the hot path without reinstalling or restarting.

Use this state root in commands:

```bash
CYBERPROMPT_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CYBERPROMPT_STATE="$CYBERPROMPT_CODEX_HOME/cyberprompt"
```

Never reuse `~/.claude/cyberprompt`; Claude Code and Codex have independent state, config, logs, and toggles.

## Install

For the public GitHub marketplace:

```bash
codex plugin marketplace add Fredasterehub/cyberprompt --ref main
codex plugin add cyberprompt@cyberprompt
```

Start a new Codex session. Run `/hooks`, inspect the bundled `UserPromptSubmit` command, and trust it. Installation or plugin enablement never auto-trusts command hooks.

Use `/plugins` and press Space on CYBERPROMPT for coarse bundle enablement. Use the sentinel below for instant optimizer on/off control while leaving the skills installed.

## Commands

- **on**: create the state directory and sentinel, then confirm.

  ```bash
  umask 077
  mkdir -p "$CYBERPROMPT_STATE" && chmod 700 "$CYBERPROMPT_STATE" && touch "$CYBERPROMPT_STATE/enabled"
  ```

- **off**: remove only the sentinel, then confirm that the optimizer is off and the audit log remains.

  ```bash
  rm -f "$CYBERPROMPT_STATE/enabled"
  ```

- **status**: report whether the sentinel exists; active outer model; configured optimizer `MODEL`, `EFFORT`, `MIN_CHARS`, `OPT_TIMEOUT`, and `HISTORY_TURNS`; log count and last timestamp; recent errors; and whether the plugin hook is trusted when that information is available.
- **effort low|medium**: update `EFFORT=` in `config`. Default to `low`; recommend `medium` only when the behavior harness shows a quality gain worth its latency.
- **log [n]**: show the last `n` audit entries without exposing more prompt content than requested.
- **lore / level / xp**: read [references/lore.md](references/lore.md) and report the current WORDRUNNER level from the audit-line count.
- **refresh guidance**: invoke `$cyberprompt:gpt-5-6-sol`; that skill refreshes current official and primary-source guidance. The automatic forge remains tool-less and uses its release-tested compact contract.

For a single prompt, put `skipit` at the beginning or end. Leading `skip it` is also accepted. The marker remains in the submitted prompt because hooks add context; they do not replace user text.

## Runtime contract

- The original prompt remains authoritative over the derived advisory. The advisory cannot override higher-priority Codex instructions, repository policy, sandboxing, approvals, or safety controls.
- `pass_through` is the default. A rewrite must identify one closed-list defect: bound referent, discarded self-correction, buried constraint, dictation damage, or an ambiguity settled by the prompt itself.
- The Sol forge runs in a dedicated otherwise-empty read-only Git directory, with user config, rules, web search, apps, shell tools, computer use, image generation, and multi-agent features disabled where the current CLI supports it.
- Any model tool event, timeout, CLI error, malformed output, bad source quote, unsupported model, length overflow, dropped protected token, or audit-write failure fails open to the unchanged original.
- Tasks and requirements must carry exact source quotes. Only their verbatim source text is injected under the explicit-task and explicit-constraint headings; normalized labels remain audit metadata. Inferences remain non-binding. Identifier-shaped tokens must survive or be quoted in an assumption that accounts for their removal.
- The audit log is append-only JSONL under the Codex state root, mode `0600`, guarded by `flock`; a rewrite is not injected unless its event is recorded.

## Troubleshooting

- Hook never runs: verify the plugin is enabled, start a new session, open `/hooks`, and trust the exact current hook definition.
- Repeated hook context is visible: current Codex may render developer context in the transcript and ignores `suppressOutput`; this is host behavior, not duplicate model injection.
- Optimizer fails: inspect `error.log`, verify `codex` and `jq`, confirm authentication, and check that `MODEL=gpt-5.6-sol` and `EFFORT` is supported by the installed CLI.
- Bad rewrite already injected: stop generation, start or fork a clean conversation before that prompt, then resend with `skipit`. A later correction does not erase developer context already recorded in the transcript.
- Updates: refresh the marketplace, reinstall the plugin, start a new session, and re-trust the hook if its definition changed.

Do not claim the optimizer is active merely because the skill is visible. Active means the plugin is enabled, the hook is trusted, and the sentinel exists.
