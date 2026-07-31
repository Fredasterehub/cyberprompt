# Deployment patterns

Snapshot date: 2026-07-31. Verify flags and fields before use.

## Codex CLI structured run

Use a stable instruction file for the reusable contract, stdin for dynamic task data, and a schema for the final artifact:

```bash
codex exec \
  --strict-config \
  --ephemeral \
  --ignore-user-config \
  --ignore-rules \
  --skip-git-repo-check \
  --sandbox read-only \
  --model gpt-5.6-sol \
  -c 'approval_policy="never"' \
  -c 'model_reasoning_effort="low"' \
  -c 'model_instructions_file="/absolute/path/instructions.md"' \
  --output-schema /absolute/path/output.schema.json \
  --output-last-message /absolute/path/result.json \
  --json \
  - < request.txt
```

For a non-agentic transform, disable unrelated features supported by the installed CLI and reject the run if its JSON event stream contains a tool, command, edit, web, computer-use, image, or subagent event.

## Codex plugin with a prompt hook

Package reusable interception as a plugin rather than claiming a skill can see every prompt:

```text
plugin/
├── .codex-plugin/plugin.json
├── hooks/hooks.json
└── skills/
    └── workflow/SKILL.md
```

`hooks/hooks.json` uses one command string:

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "bash \"${PLUGIN_ROOT}/hooks/rewrite.sh\"",
        "timeout": 200,
        "additionalContextLimit": 5000
      }]
    }]
  }
}
```

The hook receives the active `model`, `prompt`, `session_id`, `turn_id`, `transcript_path`, and optional subagent identity. Return `hookSpecificOutput.additionalContext` for developer context. Users must review and trust command hooks through `/hooks`.

## Responses API

Use the Responses API for reasoning, tools, and multi-turn state. A baseline request pins model and effort:

```json
{
  "model": "gpt-5.6-sol",
  "reasoning": {"effort": "low"},
  "input": "Produce the requested artifact from the supplied evidence."
}
```

Keep optional Pro mode, persisted reasoning, explicit caching, Programmatic Tool Calling, and multi-agent behavior out of a baseline migration. Add one only for a measured need and evaluate it separately.
