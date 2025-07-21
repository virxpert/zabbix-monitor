# Zabbix Scripts & Utilities - Development Guide

## **CRITICAL RULE: Always Review Before Coding**
Before writing ANY new code, ALWAYS check existing scripts in `/scripts/` and `/docs/` to understand patterns, logging format, and error handling. Consistency prevents bugs.

## **TEMPLATE USAGE WARNING**
Files in `/scripts/` may be TEMPLATES demonstrating proper patterns. Look for "TEMPLATE SCRIPT" headers. Never use templates as-is - always customize configuration, validation, and logic for your specific use case.

## Project Architecture
**Self-Contained Scripts**: Each script is fully independent and executable at boot time without user login. No script dependencies or shared libraries - everything needed is embedded within each script.

## Project Structure
```
/scripts/           # Self-contained executable scripts
  install-zabbix-agent.sh     # Complete Zabbix agent installation
  monitor-logs.sh             # Log file monitoring with built-in parsing
  monitor-ports.sh            # Port availability checking
  create-secure-tunnel.sh     # SSH tunnel creation with key management
  /tests/                     # Test scripts for validation
/docs/              # User documentation (installation, usage guides)
/config/            # Configuration templates and examples
/logs/              # All script logs go here (auto-created)
```

## Mandatory Standards

### Self-Contained Script Structure
Every script MUST be completely independent:
```bash
#!/bin/bash
# Script: [name] - [brief description]
# Usage: ./script.sh [options]
# Boot-safe: Can run without user login, designed for system startup
# Author: [name] | Date: [date]

set -euo pipefail  # Exit on errors, undefined vars, pipe failures

# Embedded configuration (no external config files)
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"

# Embedded logging functions (no external dependencies)
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "[$timestamp] [$level] [$SCRIPT_NAME] $message" | tee -a "$LOG_FILE"
}

# All required functions embedded here...
```

### Boot-Time Requirements
- **No External Dependencies**: All functions, configs, and logic embedded in script
- **Root Execution**: Scripts run as root during boot, handle permissions internally
- **Network Independence**: Handle network unavailability gracefully with retries
- **Silent Operation**: Minimal output, all details logged to files
- **Atomic Operations**: Each script completes one full objective independently

### Error Handling & Validation
- **Embedded Validation**: All input checking built into each script
- **Graceful Degradation**: Continue operation when non-critical components fail
- **Retry Logic**: Network operations have built-in retry with exponential backoff
- **Exit Codes**: 0=success, 1=general error, 2=invalid input, 3=network timeout
- **Lock Files**: Use `/var/run/[script-name].pid` to prevent concurrent execution

## Development Workflow

### Before Writing Code
1. Read existing scripts in `/scripts/` to understand the self-contained patterns
2. **IDENTIFY TEMPLATES**: Look for "TEMPLATE SCRIPT" headers - these are examples, not production scripts
3. Check `/docs/` for existing functionality and user expectations
4. Review test patterns in `/tests/` for validation approaches
5. Understand boot-time constraints and network availability issues

### Creating New Scripts
1. **Start with template**: Copy structure from template scripts, customize all logic
2. Single file approach: `[action-target].sh` (e.g., `install-zabbix-agent.sh`)
3. Embed ALL required functions, configs, and logic within the script
4. **Customize configuration block**: Update servers, paths, timeouts for your environment
5. **Implement specific logic**: Replace template functions with actual requirements
6. Create corresponding test in `/tests/test-[script-name].sh`
7. Design for unattended execution during system boot
8. Update documentation in `/docs/`

### Boot-Time Testing
- Test scripts as root without login session
- Simulate network unavailability scenarios  
- Validate operation during early boot stages
- Test concurrent execution prevention (lock files)
- Verify log file creation and permissions

## User-Focused Design
Scripts will be used by non-programmers and system administrators:
- **Unattended Operation**: Scripts run automatically during boot without interaction
- **Clear Configuration**: Use embedded config sections with comments for easy modification
- **Self-Documenting**: Include usage examples within script headers
- **Status Reporting**: Log all actions and outcomes for post-execution review
- **Recovery Mechanisms**: Built-in rollback or recovery procedures for failed operations

## Self-Contained Script Patterns
Each script must embed these components:
- **Configuration Block**: All settings at the top of the script
- **Utility Functions**: Logging, validation, network checks, etc.
- **Main Logic**: Complete functionality without external calls
- **Cleanup Procedures**: Proper cleanup on exit or failure
- **Status Reporting**: Success/failure indication via logs and exit codes

## Documentation Structure
Keep documentation minimal but comprehensive:
- `README.md` - Quick start and boot integration guide
- `/docs/installation.md` - System integration and systemd service setup
- `/docs/usage.md` - Configuration and customization examples
- `/docs/troubleshooting.md` - Boot-time issues and log analysis

Remember: Each script is a complete, standalone solution. No dependencies, no shared state, no inter-script communication. Design for reliability in unattended, boot-time environments.
