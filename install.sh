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
cp "$DIR/hooks/schema.json" "$STATE/schema.json"
[ -f "$STATE/config" ] || cp "$DIR/hooks/config.example" "$STATE/config"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
CMD='$HOME/.claude/hooks/cyberprompt.sh'
jq --arg cmd "$CMD" '
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
    | if any(.[]?.hooks[]?; .command == $cmd) then .
      else . + [{hooks: [{type: "command", command: $cmd, timeout: 90}]}] end)
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "cyberprompt installed (disabled by default)."
echo "  Enable:  touch $STATE/enabled"
echo "  Disable: rm -f $STATE/enabled"
echo "  Config:  $STATE/config (MODEL, EFFORT, MIN_CHARS, CLAUDE5_SKILL)"
echo "  Skills:  $SKILLS/cyberprompt (management), $SKILLS/claude-5 (bundled; kept as-is if already present — rm -rf it and re-run to refresh)"
echo "  Note:    installing the plugin later? Remove this hook entry from $SETTINGS first, or the hook runs twice."
