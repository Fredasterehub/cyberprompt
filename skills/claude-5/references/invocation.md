# Invoking Claude 5 models from Claude Code

How to route any task to any model, from every surface.

## Invocation surfaces

| Surface | Model control | Effort control | Notes |
|---|---|---|---|
| Agent tool (in-session) | `model: "fable" \| "opus" \| "sonnet" \| "haiku"` | none per-call — inherits session | `subagent_type: "fork"` always runs the parent model; the override is ignored |
| Workflow `agent()` | `opts.model`, same values | `opts.effort: "low"…"max"` | fullest per-call control; omit both to inherit the session model/effort |
| `.claude/agents/*.md` | `model:` frontmatter — alias, full model ID, or `inherit` (default) | `effort:` frontmatter | also: `tools` allowlist, `background`, `isolation: worktree`, `maxTurns` |
| Skill / command frontmatter | `model:` | `effort:` | override applies only to the invoking turn |
| CLI | `claude --model …`, `claude agents … --model … --effort …` | `--effort` | `claude -p` for headless/scripting |
| Messages API | `model: "claude-fable-5" / "claude-opus-5" / "claude-sonnet-5"` | `output_config: {"effort": "…"}` | parameter rules in `shared.md` pre-flight |

## Operational facts

- Subagents inherit the session's permission mode.
- MCP tool schemas are deferred inside subagents — load them with `ToolSearch("select:mcp__server__tool,…")` before calling.
- The Playwright MCP server is one shared browser: serialize browser-using agents (or they contend on state) and have each one call `browser_close` when done.
