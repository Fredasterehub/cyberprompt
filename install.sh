#!/usr/bin/env bash
# Installs the cyberprompt hook for the current user.
# Idempotent: safe to re-run; never overwrites an existing config/instruction.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.claude/hooks"
STATE="$HOME/.claude/cyberprompt"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOOKS" "$STATE"
cp "$DIR/hook/cyberprompt.sh" "$HOOKS/cyberprompt.sh"
chmod +x "$HOOKS/cyberprompt.sh"
[ -f "$STATE/instruction.txt" ] || cp "$DIR/hook/instruction.txt" "$STATE/instruction.txt"
cp "$DIR/hook/schema.json" "$STATE/schema.json"
[ -f "$STATE/config" ] || cp "$DIR/hook/config.example" "$STATE/config"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
CMD='$HOME/.claude/hooks/cyberprompt.sh'
jq --arg cmd "$CMD" '
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
    | if any(.[]?.hooks[]?; .command == $cmd) then .
      else . + [{hooks: [{type: "command", command: $cmd, timeout: 180}]}] end)
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "cyberprompt installed (disabled by default)."
echo "  Enable:  touch $STATE/enabled"
echo "  Disable: rm -f $STATE/enabled"
echo "  Config:  $STATE/config (MODEL, MIN_CHARS)"
