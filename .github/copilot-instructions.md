# Zabbix Scripts & Utilities - Development Guide

## **CRITICAL RULE: Always Review Before Coding**
Before writing ANY new code, ALWAYS check existing scripts in `/scripts/` and `/docs/` to understand patterns, logging format, and error handling. Consistency prevents bugs.

## **TEMPLATE USAGE WARNING**
Files in `/scripts/` may be TEMPLATES demonstrating proper patterns. Look for "TEMPLATE SCRIPT" headers. Never use templates as-is - always customize configuration, validation, and logic for your specific use case.

## **VIRTUALIZOR DEPLOYMENT CONTEXT**
These scripts are designed for execution during Linux server provisioning using **Virtualizor software recipes**. This means:
- Scripts execute during VM/server creation and initial configuration
- Must handle fresh OS installations with minimal packages
- Need to work reliably in automated provisioning environments
- Should complete successfully without manual intervention
- May run multiple times during different provisioning phases
- **CRITICAL**: Must handle system reboots during update process with state persistence

## Project Architecture
**Unified Provisioning Pipeline**: The master script (`virtualizor-server-setup.sh`) orchestrates the complete server lifecycle to prevent conflicts with other boot-time scripts:

### Master Script Approach (RECOMMENDED)
- **Single Point of Execution**: `virtualizor-server-setup.sh` handles entire server setup lifecycle
- **Reboot Persistence**: Maintains state across required reboots using systemd services and state files
- **Stage-Based Execution**: Progresses through defined stages (banner → updates → reboot → zabbix install → tunnel setup)
- **Conflict Prevention**: Eliminates race conditions with other boot scripts by consolidating all operations
- **Idempotent Operations**: Can safely resume from any stage if interrupted

### Legacy Scripts (ARCHIVED)
Individual scripts in `/archive/legacy-scripts/` have been superseded by the master script and should only be used for:
- Reference implementations for specific functions
- Manual server maintenance (after updating for current infrastructure)
- Educational purposes to understand individual components

## Project Structure
```
/scripts/           # Production-ready scripts
  virtualizor-server-setup.sh    # MASTER: Complete server provisioning pipeline
/docs/              # User documentation (installation, usage guides)
/archive/           # Legacy scripts and deprecated files
  /legacy-scripts/  # Individual scripts superseded by master script
    configure-zabbix.sh           # SSH tunnel configuration (archived)
  /tests/          # Development test scripts (Windows incompatible)
/logs/              # All script logs go here (auto-created)
```

## **CRITICAL: Master Script Usage for Virtualizor**
For Virtualizor deployments, **ALWAYS use the master script**:
```bash
# Virtualizor recipe usage:
/path/to/virtualizor-server-setup.sh

# Manual execution:
./virtualizor-server-setup.sh [--stage init] [--banner-text "Custom Text"]
```

**Master Script Features:**
- **State Persistence**: Maintains execution state across reboots via `/var/run/virtualizor-server-setup.state`
- **Systemd Integration**: Creates temporary service for reboot persistence
- **Stage Management**: Progresses through: init → banner → updates → post-reboot → zabbix-install → zabbix-configure → tunnel-setup → complete
- **Conflict Prevention**: Single execution point eliminates race conditions with other boot scripts
- **Recovery Support**: Can resume from any stage if interrupted

## Mandatory Standards

### Self-Contained Script Structure
Every script MUST be completely independent:
```bash
#!/bin/bash
# Script: [name] - [brief description]
# Usage: ./script.sh [options]
# Virtualizor-ready: Designed for automated server provisioning
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

### Virtualizor Recipe Requirements
- **No External Dependencies**: All functions, configs, and logic embedded in script
- **Root Execution**: Scripts run as root during provisioning, handle permissions internally
- **Fresh OS Compatibility**: Handle minimal package installations and missing utilities
- **Network Resilience**: Handle unstable network during initial server setup with retries
- **Silent Operation**: Minimal output, all details logged to files for post-provision review
- **Idempotent Operations**: Can run multiple times safely during provisioning phases
- **Quick Execution**: Optimize for fast completion to avoid provisioning timeouts

### Error Handling & Validation
- **Embedded Validation**: All input checking built into each script
- **Graceful Degradation**: Continue operation when non-critical components fail
- **Retry Logic**: Network and package operations with built-in retry and exponential backoff
- **Exit Codes**: 0=success, 1=general error, 2=invalid input, 3=network timeout, 4=provisioning timeout
- **Lock Files**: Use `/var/run/[script-name].pid` to prevent concurrent execution
- **Provisioning Compatibility**: Handle interrupted provisioning and recipe re-runs

## Development Workflow

### Before Writing Code
1. Read existing scripts in `/scripts/` to understand the self-contained patterns
2. **IDENTIFY TEMPLATES**: Look for "TEMPLATE SCRIPT" headers - these are examples, not production scripts
3. Check `/docs/` for existing functionality and user expectations
4. Review test patterns in `/tests/` for validation approaches
5. Understand Virtualizor provisioning constraints and network availability issues
6. **PREFER MASTER SCRIPT**: For new Virtualizor features, enhance the master script rather than creating individual scripts

### Creating New Scripts
**IMPORTANT**: For Virtualizor provisioning, enhance `virtualizor-server-setup.sh` rather than creating new individual scripts.

For specialized maintenance/troubleshooting scripts:
1. **Start with existing patterns**: Review archived legacy scripts for reference
2. Single file approach: `[action-target].sh` (e.g., `backup-config.sh`)
3. Embed ALL required functions, configs, and logic within the script
4. **Customize configuration block**: Update servers, paths, timeouts for your environment
5. **Implement specific logic**: Build upon proven patterns from master script
6. Design for manual execution (not automated provisioning)
7. Update documentation in `/docs/`

### Master Script Enhancement
When enhancing the master script (`virtualizor-server-setup.sh`):
1. **Add new stages** to the stage progression if needed
2. **Embed functionality** within the master script to maintain single-file approach
3. **Update stage transitions** to include new functionality
4. **Maintain state persistence** across any new reboot requirements
5. **Test stage isolation** - each stage must be resumable

### Virtualizor Integration Testing
- Test scripts as root during fresh OS installation
- Simulate network unavailability and package repository issues
- Validate operation during different provisioning phases  
- Test concurrent execution prevention (lock files)
- Verify log file creation and permissions during provisioning

## User-Focused Design
Scripts will be used by system administrators in automated Virtualizor environments:
- **Unattended Provisioning**: Scripts execute automatically during server creation without interaction
- **Clear Configuration**: Use embedded config sections with comments for easy customization
- **Self-Documenting**: Include usage examples and Virtualizor integration notes within script headers
- **Status Reporting**: Log all actions and outcomes for post-provisioning review
- **Recovery Mechanisms**: Built-in rollback or recovery procedures for failed provisioning steps

## Self-Contained Script Patterns
Each script must embed these components:
- **Configuration Block**: All settings at the top of the script
- **Utility Functions**: Logging, validation, network checks, etc.
- **Main Logic**: Complete functionality without external calls
- **Cleanup Procedures**: Proper cleanup on exit or failure
- **Status Reporting**: Success/failure indication via logs and exit codes

## Documentation Structure
Keep documentation minimal but comprehensive for Virtualizor environments:
- `README.md` - Quick start and Virtualizor integration guide
- `/docs/installation.md` - Recipe integration and automated deployment setup
- `/docs/usage.md` - Configuration and customization for different provisioning scenarios
- `/docs/troubleshooting-guide.md` - Provisioning issues, log analysis, and debugging during server creation

Remember: Each script is a complete, standalone solution. No dependencies, no shared state, no inter-script communication. Design for reliability in unattended, automated provisioning environments.
