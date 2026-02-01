#!/bin/bash
# Pre-Plan Security Hook for Threat Modeling Toolkit
# Triggered on: PreToolUse -> EnterPlanMode
# Purpose: Quick risk assessment before implementation planning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE="${PROJECT_ROOT}/.threatmodel/config.yaml"
GLOBAL_CONFIG="${HOME}/.claude/threat-modeling.yaml"

# Default configuration
ENABLED=true
SKILL="tm-quick"
BLOCK_ON="critical"
FOCUS_ON_CHANGED=true
TIMEOUT=60

# Parse configuration
parse_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        # Extract hook settings using grep/sed (portable YAML parsing)
        ENABLED=$(grep -A 10 "pre_plan:" "$config_file" | grep "enabled:" | head -1 | awk '{print $2}' | tr -d '"' || echo "true")
        SKILL=$(grep -A 10 "pre_plan:" "$config_file" | grep "skill:" | head -1 | awk '{print $2}' | tr -d '"' || echo "tm-quick")
        BLOCK_ON=$(grep -A 10 "pre_plan:" "$config_file" | grep "block_on:" | head -1 | awk '{print $2}' | tr -d '"' || echo "critical")
        TIMEOUT=$(grep -A 10 "pre_plan:" "$config_file" | grep "timeout_seconds:" | head -1 | awk '{print $2}' || echo "60")
    fi
}

# Load configuration (project overrides global)
if [[ -f "$GLOBAL_CONFIG" ]]; then
    parse_config "$GLOBAL_CONFIG"
fi
if [[ -f "$CONFIG_FILE" ]]; then
    parse_config "$CONFIG_FILE"
fi

# Check if hook is enabled
if [[ "$ENABLED" == "false" ]]; then
    echo '{"status": "skipped", "reason": "pre_plan hook disabled"}'
    exit 0
fi

# Check if skill is "none"
if [[ "$SKILL" == "none" ]]; then
    echo '{"status": "skipped", "reason": "pre_plan skill set to none"}'
    exit 0
fi

# Determine focus scope
FOCUS_ARG=""
if [[ "$FOCUS_ON_CHANGED" == "true" ]]; then
    # Try to detect changed files from git
    if git rev-parse --git-dir > /dev/null 2>&1; then
        CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$CHANGED_FILES" ]]; then
            FOCUS_ARG="--focus $CHANGED_FILES"
        fi
    fi
fi

# Execute the threat analysis skill
# Output format must be JSON for hook processing
RESULT=$(timeout "$TIMEOUT" claude --print "Run /${SKILL} --format json ${FOCUS_ARG}" 2>/dev/null || echo '{"risk_level": "unknown", "error": "Analysis timed out or failed"}')

# Parse risk level from result
RISK_LEVEL=$(echo "$RESULT" | grep -o '"risk_level"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "unknown")

# Determine if we should block
should_block() {
    local risk="$1"
    local threshold="$2"

    # Risk level ordering: none < low < medium < high < critical
    declare -A levels=([none]=0 [low]=1 [medium]=2 [high]=3 [critical]=4)

    local risk_val=${levels[$risk]:-0}
    local threshold_val=${levels[$threshold]:-4}

    if [[ $risk_val -ge $threshold_val && "$threshold" != "none" ]]; then
        return 0  # Should block
    fi
    return 1  # Should not block
}

# Output result with blocking decision
if should_block "$RISK_LEVEL" "$BLOCK_ON"; then
    # Add blocking indicator to result
    echo "$RESULT" | sed 's/}$/,"hook_action": "block", "block_reason": "Risk level '"$RISK_LEVEL"' meets or exceeds threshold '"$BLOCK_ON"'"}/'
    exit 1  # Non-zero exit blocks the action
else
    echo "$RESULT" | sed 's/}$/,"hook_action": "allow"}/'
    exit 0
fi
