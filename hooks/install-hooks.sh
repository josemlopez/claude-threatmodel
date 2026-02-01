#!/bin/bash
# Install Threat Modeling Hooks into Claude Code settings
# Run this script after installing the plugin to enable automated security checks

set -e

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Threat Modeling Hooks..."
echo ""

# Check if settings file exists
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "Creating Claude Code settings file..."
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    echo '{}' > "$CLAUDE_SETTINGS"
fi

# Backup existing settings
cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d%H%M%S)"

# Create hook configuration
HOOKS_CONFIG=$(cat <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "EnterPlanMode",
        "command": ["bash", "-c", "PROJECT_ROOT=$(pwd) /path/to/hooks/pre-plan-hook.sh"]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "ExitPlanMode",
        "command": ["bash", "-c", "PROJECT_ROOT=$(pwd) /path/to/hooks/post-plan-hook.sh"]
      }
    ]
  }
}
EOF
)

# Update paths in hook config
HOOKS_CONFIG=$(echo "$HOOKS_CONFIG" | sed "s|/path/to/hooks|$SCRIPT_DIR|g")

# Merge with existing settings using jq if available, otherwise provide instructions
if command -v jq &> /dev/null; then
    # Use jq to merge settings
    EXISTING=$(cat "$CLAUDE_SETTINGS")
    NEW_HOOKS=$(echo "$HOOKS_CONFIG" | jq '.hooks')

    echo "$EXISTING" | jq --argjson hooks "$NEW_HOOKS" '. + {hooks: $hooks}' > "$CLAUDE_SETTINGS"

    echo "Hooks installed successfully!"
    echo ""
    echo "Installed hooks:"
    echo "  - PreToolUse (EnterPlanMode): pre-plan-hook.sh"
    echo "  - PostToolUse (ExitPlanMode): post-plan-hook.sh"
else
    echo "jq not found. Please manually add the following to $CLAUDE_SETTINGS:"
    echo ""
    echo "$HOOKS_CONFIG"
    echo ""
    echo "Or install jq and run this script again: brew install jq (macOS) or apt install jq (Linux)"
fi

echo ""
echo "Configuration:"
echo "  - Pre-plan hook: Enabled by default, runs tm-quick, blocks on critical"
echo "  - Post-plan hook: Disabled by default, runs tm-full when enabled"
echo ""
echo "To customize, edit .threatmodel/config.yaml in your project or ~/.claude/threat-modeling.yaml globally"
