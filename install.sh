#!/usr/bin/env bash
# Manual (no-plugin) installer for cyberprompt. Prefer the plugin route:
#   /plugin marketplace add Fredasterehub/cyberprompt && /plugin install cyberprompt@cyberprompt
# This script exists for setups that don't use plugins: it copies the hook,
# seeds the state dir, installs both skills, and registers the hook in
# ~/.claude/settings.json. Idempotent: safe to re-run; never overwrites an
# existing config/instruction or a user's own claude-5 skill.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.claude/hooks"
STATE="$HOME/.claude/cyberprompt"
SKILLS="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOOKS" "$STATE" "$SKILLS"

# claude-5 prompting skill: seed only when absent — never clobber the user's own.
if [ ! -e "$SKILLS/claude-5" ] && [ ! -L "$SKILLS/claude-5" ]; then
  cp -r "$DIR/skills/claude-5" "$SKILLS/claude-5"
elif [ -L "$SKILLS/claude-5" ] && [ ! -e "$SKILLS/claude-5" ]; then
  echo "warning: $SKILLS/claude-5 is a broken symlink — left untouched; fix or remove it and re-run." >&2
fi

# cyberprompt management skill: product-owned, refreshed on every run.
if [ ! -e "$SKILLS/cyberprompt" ]; then
  cp -r "$DIR/skills/cyberprompt" "$SKILLS/cyberprompt"
elif [ "$(cd "$DIR/skills/cyberprompt" && pwd -P)" != "$(cd "$SKILLS/cyberprompt" && pwd -P)" ]; then
  cp "$DIR/skills/cyberprompt/SKILL.md" "$DIR/skills/cyberprompt/LORE.md" "$SKILLS/cyberprompt/"
fi

cp "$DIR/hooks/cyberprompt.sh" "$HOOKS/cyberprompt.sh"
chmod +x "$HOOKS/cyberprompt.sh"
[ -f "$STATE/instruction.txt" ] || cp "$DIR/hooks/instruction.txt" "$STATE/instruction.txt"
if ! grep -q '{{CEILING}}' "$STATE/instruction.txt"; then
  echo "warning: $STATE/instruction.txt predates the {{CEILING}} length-budget placeholder — merge the current hooks/instruction.txt into it (or delete it to re-seed). The hook still delivers the budget via a fallback line, but the template's phrasing is better." >&2
fi
if ! grep -q 'BACKGROUND CONTEXT' "$STATE/instruction.txt"; then
  echo "warning: $STATE/instruction.txt predates the BACKGROUND CONTEXT rules — the hook now feeds the optimizer a bounded slice of recent session turns, and without those rules the model gets the context but not the discipline (requirements only from the raw prompt, topic-switch discard). Merge the current hooks/instruction.txt into it, or delete it to re-seed." >&2
fi
if ! grep -q 'QUOTED VERBATIM inside an assumption' "$STATE/instruction.txt"; then
  echo "warning: $STATE/instruction.txt predates the v0.0.3 spoken-input rules (self-repair resolution, question/hedge preservation, bounded ASR repair, retention accounting) — the retention gate still protects tokens, but the optimizer won't know to quote justified drops in assumptions. Merge the current hooks/instruction.txt into it, or delete it to re-seed." >&2
fi
cp "$DIR/hooks/schema.json" "$STATE/schema.json"
[ -f "$STATE/config" ] || cp "$DIR/hooks/config.example" "$STATE/config"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
CMD='$HOME/.claude/hooks/cyberprompt.sh'
jq --arg cmd "$CMD" '
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
    | if any(.[]?.hooks[]?; .command == $cmd)
      then map(if any(.hooks[]?; .command == $cmd)
        then .hooks |= map(if .command == $cmd then .timeout = 200 else . end)
        else . end)
      else . + [{hooks: [{type: "command", command: $cmd, timeout: 200}]}] end)
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "cyberprompt installed (disabled by default)."
echo "  Enable:  touch $STATE/enabled"
echo "  Disable: rm -f $STATE/enabled"
echo "  Config:  $STATE/config (MODEL, EFFORT, MIN_CHARS, OPT_TIMEOUT, HISTORY_TURNS — 0 disables transcript reading, CLAUDE5_SKILL)"
echo "  Skills:  $SKILLS/cyberprompt (management), $SKILLS/claude-5 (bundled; kept as-is if already present — rm -rf it and re-run to refresh)"
echo "  Note:    installing the plugin later? Remove this hook entry from $SETTINGS first, or the hook runs twice."
