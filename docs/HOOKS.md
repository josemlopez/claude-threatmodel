# Automated Security Hooks

The Threat Modeling Toolkit includes automated hooks that integrate with Claude Code to provide security analysis at key points in your development workflow.

## Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  User Request   │────▶│  EnterPlanMode  │────▶│  ExitPlanMode   │
│  "Add feature"  │     │                 │     │                 │
└─────────────────┘     └────────┬────────┘     └────────┬────────┘
                                 │                       │
                        ┌────────▼────────┐     ┌────────▼────────┐
                        │   PRE-PLAN      │     │   POST-PLAN     │
                        │   HOOK          │     │   HOOK          │
                        │                 │     │                 │
                        │ • Quick scan    │     │ • Full analysis │
                        │ • Top threats   │     │ • Compliance    │
                        │ • Block/Allow   │     │ • Baseline      │
                        └─────────────────┘     └─────────────────┘
```

## Installation

After installing the plugin, run the hook installation script:

```bash
cd /path/to/threat-modeling-toolkit
./hooks/install-hooks.sh
```

This adds the hooks to your Claude Code settings (`~/.claude/settings.json`).

## Pre-Plan Hook

**Trigger:** When you enter plan mode (`EnterPlanMode`)

**Purpose:** Quick risk assessment before implementation planning

**Default behavior:**

- Runs `/tm-quick` for fast threat analysis (~30 seconds)
- Returns top 3-5 threats and critical gaps
- Blocks plan mode if risk level is `critical`

### Configuration

```yaml
# .threatmodel/config.yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-quick" # Options: tm-quick, tm-threats, none
    block_on: "critical" # Options: none, low, medium, high, critical
    focus_on_changed: true # Scope to changed files
    timeout_seconds: 60
```

### Output Example

```json
{
  "risk_level": "high",
  "risk_score": 14,
  "top_threats": [
    {
      "id": "threat-001",
      "title": "SQL Injection in user input",
      "severity": "critical",
      "target": "src/routes/api.js:45"
    }
  ],
  "critical_gaps": [
    {
      "id": "gap-001",
      "title": "Missing input validation",
      "severity": "high"
    }
  ],
  "recommendation": "Address 1 critical threat before proceeding.",
  "hook_action": "allow"
}
```

### Blocking Behavior

| Risk Level | `block_on: critical` | `block_on: high` | `block_on: medium` |
| ---------- | -------------------- | ---------------- | ------------------ |
| critical   | BLOCK                | BLOCK            | BLOCK              |
| high       | allow                | BLOCK            | BLOCK              |
| medium     | allow                | allow            | BLOCK              |
| low        | allow                | allow            | allow              |

## Post-Plan Hook

**Trigger:** When you exit plan mode (`ExitPlanMode`)

**Purpose:** Comprehensive analysis after plan approval

**Default behavior:**

- Disabled by default (enable for security-critical projects)
- Runs `/tm-full` for complete threat analysis
- Creates baseline snapshot for drift detection
- Non-blocking (informational only)

### Configuration

```yaml
# .threatmodel/config.yaml
hooks:
  post_plan:
    enabled: true # Enable for security-critical work
    skill: "tm-full" # Options: tm-full, tm-verify, tm-compliance, none
    compliance:
      - "owasp"
      - "soc2"
    auto_baseline: true # Create snapshot after analysis
    generate_report: true
    timeout_seconds: 180
```

## Configuration Scenarios

### Fast Iteration (Default)

For rapid development with minimal friction:

```yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-quick"
    block_on: "critical" # Only block on critical issues
  post_plan:
    enabled: false
```

### Security-Critical Mode

For sensitive features (auth, payments, PII handling):

```yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-quick"
    block_on: "high" # Block on high and critical
  post_plan:
    enabled: true
    skill: "tm-full"
    compliance:
      - "owasp"
      - "soc2"
      - "pci-dss"
    auto_baseline: true
```

### Compliance Mode

For audit-ready development:

```yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-threats" # More thorough pre-plan analysis
    block_on: "medium"
  post_plan:
    enabled: true
    skill: "tm-compliance"
    compliance:
      - "soc2"
      - "hipaa"
    auto_baseline: true
    generate_report: true
```

### Learning Mode

For exploration without blocking:

```yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-quick"
    block_on: "none" # Never block, just inform
  post_plan:
    enabled: false
```

## Global vs Project Configuration

Hooks can be configured at two levels:

1. **Global** (`~/.claude/threat-modeling.yaml`): Default for all projects
2. **Project** (`.threatmodel/config.yaml`): Override for specific project

Project settings take precedence over global settings.

### Example Global Config

```yaml
# ~/.claude/threat-modeling.yaml
hooks:
  pre_plan:
    enabled: true
    skill: "tm-quick"
    block_on: "critical"
  post_plan:
    enabled: false
```

## Troubleshooting

### Hook not triggering

1. Check if hooks are installed: `cat ~/.claude/settings.json | grep -A 10 hooks`
2. Verify hook scripts are executable: `ls -la hooks/*.sh`
3. Run install script again: `./hooks/install-hooks.sh`

### Analysis timing out

Increase timeout in config:

```yaml
hooks:
  pre_plan:
    timeout_seconds: 120 # Increase from default 60
```

### Too many false positives blocking

Adjust threshold:

```yaml
hooks:
  pre_plan:
    block_on: "critical" # Only block on critical, not high
```

### Disable hooks temporarily

```yaml
hooks:
  pre_plan:
    enabled: false
  post_plan:
    enabled: false
```

## Manual Execution

You can run the hooks manually for testing:

```bash
# Pre-plan analysis
PROJECT_ROOT=$(pwd) ./hooks/pre-plan-hook.sh

# Post-plan analysis
PROJECT_ROOT=$(pwd) ./hooks/post-plan-hook.sh
```

## Integration with CI/CD

The hooks can also be used in CI/CD pipelines:

```yaml
# .github/workflows/security.yml
- name: Security Analysis
  run: |
    ./hooks/pre-plan-hook.sh
    if [ $? -ne 0 ]; then
      echo "Security check failed"
      exit 1
    fi
```
