#!/bin/bash
# Post-Plan Security Hook for Threat Modeling Toolkit
# Triggered on: PostToolUse -> ExitPlanMode
# Purpose: Comprehensive threat analysis after plan approval

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE="${PROJECT_ROOT}/.threatmodel/config.yaml"
GLOBAL_CONFIG="${HOME}/.claude/threat-modeling.yaml"

# Default configuration
ENABLED=false
SKILL="tm-full"
COMPLIANCE=""
AUTO_BASELINE=true
GENERATE_REPORT=true
TIMEOUT=180

# Parse configuration
parse_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        ENABLED=$(grep -A 15 "post_plan:" "$config_file" | grep "enabled:" | head -1 | awk '{print $2}' | tr -d '"' || echo "false")
        SKILL=$(grep -A 15 "post_plan:" "$config_file" | grep "skill:" | head -1 | awk '{print $2}' | tr -d '"' || echo "tm-full")
        AUTO_BASELINE=$(grep -A 15 "post_plan:" "$config_file" | grep "auto_baseline:" | head -1 | awk '{print $2}' || echo "true")
        GENERATE_REPORT=$(grep -A 15 "post_plan:" "$config_file" | grep "generate_report:" | head -1 | awk '{print $2}' || echo "true")
        TIMEOUT=$(grep -A 15 "post_plan:" "$config_file" | grep "timeout_seconds:" | head -1 | awk '{print $2}' || echo "180")

        # Parse compliance array
        COMPLIANCE=$(grep -A 20 "post_plan:" "$config_file" | grep -A 10 "compliance:" | grep "^\s*-" | sed 's/.*- *"\?\([^"]*\)"\?.*/\1/' | tr '\n' ',' | sed 's/,$//')
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
if [[ "$ENABLED" != "true" ]]; then
    echo '{"status": "skipped", "reason": "post_plan hook disabled"}'
    exit 0
fi

# Check if skill is "none"
if [[ "$SKILL" == "none" ]]; then
    echo '{"status": "skipped", "reason": "post_plan skill set to none"}'
    exit 0
fi

# Build skill arguments
SKILL_ARGS=""
if [[ -n "$COMPLIANCE" ]]; then
    SKILL_ARGS="--compliance $COMPLIANCE"
fi

# Execute the threat analysis skill
echo '{"status": "running", "skill": "'"$SKILL"'", "compliance": "'"$COMPLIANCE"'"}'

RESULT=$(timeout "$TIMEOUT" claude --print "Run /${SKILL} ${SKILL_ARGS}" 2>/dev/null || echo '{"status": "error", "error": "Analysis timed out or failed"}')

# Create baseline if enabled
if [[ "$AUTO_BASELINE" == "true" && -d "${PROJECT_ROOT}/.threatmodel" ]]; then
    BASELINE_DATE=$(date +%Y%m%d-%H%M%S)
    BASELINE_DIR="${PROJECT_ROOT}/.threatmodel/baseline"
    mkdir -p "$BASELINE_DIR"

    # Copy current state to baseline
    if [[ -d "${PROJECT_ROOT}/.threatmodel/state" ]]; then
        cp -r "${PROJECT_ROOT}/.threatmodel/state" "${BASELINE_DIR}/snapshot-${BASELINE_DATE}"
        echo "Baseline created: snapshot-${BASELINE_DATE}"
    fi
fi

# Output result (informational, non-blocking)
echo "$RESULT" | sed 's/}$/,"hook_action": "complete", "baseline_created": '"$AUTO_BASELINE"'}/'
exit 0
