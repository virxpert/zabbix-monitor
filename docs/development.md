# Development Guide

This document provides detailed guidance for developers working on the Zabbix Scripts & Utilities project.

## Before You Start

### ⚠️ CRITICAL: Always Review Existing Code
Before writing ANY new script, you MUST:

1. **Read existing scripts** in `/scripts/` to understand established patterns
2. **Identify templates** by looking for "TEMPLATE SCRIPT" headers
3. **Check documentation** in `/docs/` for existing functionality
4. **Review test patterns** in `/scripts/tests/` for validation approaches
5. **Understand constraints** of boot-time, no-login execution environment

### Template vs Production Scripts

**Template Scripts** are marked with:
```bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING  
# ====================================================================
# This is a REFERENCE TEMPLATE demonstrating proper script structure
# DO NOT use as-is - customize configuration and logic for your needs
```

**Never use templates as production scripts**. They are reference examples showing proper structure and patterns.

## Script Development Process

### 1. Planning Phase

**Define Objective**: Each script must complete ONE specific objective independently:
- ✅ Good: "Install and configure Zabbix agent"
- ❌ Bad: "Install Zabbix agent and monitor logs and create tunnels"

**Identify Requirements**:
- What configuration values need customization?
- What network dependencies exist?
- What files/services will be modified?
- What validation is needed?
- What recovery procedures are required?

### 2. Template Selection

**Choose appropriate template** based on your objective:
- `install-zabbix-agent.sh` - Package installation and service configuration
- `monitor-logs.sh` - File monitoring and parsing (planned)
- `monitor-ports.sh` - Network connectivity checking (planned)
- `create-secure-tunnel.sh` - SSH/VPN tunnel management (planned)

**Copy template structure**:
```bash
cp scripts/install-zabbix-agent.sh scripts/my-new-script.sh
```

### 3. Customization Requirements

**Embedded Configuration Section**:
```bash
# ====================================================================
# EMBEDDED CONFIGURATION (no external config files)
# ====================================================================
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME}.pid"

# Custom configuration - CHANGE THESE VALUES
readonly DEFAULT_SERVER="your.server.com"
readonly DEFAULT_PORT="1234"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=10
```

**Update ALL placeholder values**:
- Server addresses, hostnames, ports
- Timeouts, retry counts, delays  
- File paths, directory locations
- Service names, package names

### 4. Implementation Guidelines

**Function Structure**:
Every script must include these embedded functions:

```bash
# ====================================================================
# EMBEDDED LOGGING FUNCTIONS (no external dependencies)
# ====================================================================
log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

# ====================================================================  
# EMBEDDED UTILITY FUNCTIONS
# ====================================================================
create_lock_file() { ... }
cleanup() { ... }
validate_root() { ... }
check_network_connectivity() { ... }

# ====================================================================
# MAIN LOGIC FUNCTIONS
# ====================================================================
detect_os() { ... }
install_packages() { ... }
configure_service() { ... }
validate_installation() { ... }
```

**Error Handling**:
```bash
# Always use error handling pattern
operation_name() {
    local param1="$1"
    
    log_info "Starting operation_name with param: $param1"
    
    # Attempt operation with validation
    if ! command_that_might_fail "$param1" >/dev/null 2>&1; then
        log_error "Failed to execute operation_name"
        return 1
    fi
    
    log_info "Operation_name completed successfully"
    return 0
}
```

**Network Operations**:
```bash
# Always include retry logic for network operations
network_operation() {
    local target="$1"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if ping -c 1 -W 5 "$target" >/dev/null 2>&1; then
            log_info "Network operation successful"
            return 0
        fi
        
        retries=$((retries + 1))
        local delay=$((RETRY_DELAY * retries))
        log_warn "Network operation failed (attempt $retries/$MAX_RETRIES). Retrying in ${delay}s..."
        sleep $delay
    done
    
    log_error "Network operation failed after $MAX_RETRIES attempts"
    return 3
}
```

### 5. Boot-Time Considerations

**Silent Operation**:
```bash
# Redirect command output, log results
if yum install -y package >/dev/null 2>&1; then
    log_info "Package installed successfully"
else
    log_error "Package installation failed"
    return 1
fi
```

**Root Execution**:
```bash
# Always validate root privileges
validate_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 2
    fi
}
```

**Lock File Management**:
```bash
# Prevent concurrent execution
create_lock_file() {
    if [ -f "$LOCK_FILE" ]; then
        local existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            log_error "Script already running with PID $existing_pid"
            exit 1
        fi
        log_warn "Removing stale lock file"
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    log_info "Created lock file with PID $$"
}
```

## Testing Requirements

### Test Script Creation

**Every script requires a corresponding test**:
```bash
scripts/
  install-zabbix-agent.sh
  tests/
    test-install-zabbix-agent.sh
```

**Test script structure**:
```bash
#!/bin/bash
# Test script for install-zabbix-agent.sh

set -euo pipefail

readonly TEST_SCRIPT="../install-zabbix-agent.sh"
readonly TEST_LOG="/tmp/test-install-zabbix-agent.log"

test_help_display() {
    echo "Testing help display..."
    if $TEST_SCRIPT --help >/dev/null 2>&1; then
        echo "✓ Help display works"
        return 0
    else
        echo "✗ Help display failed"
        return 1
    fi
}

test_invalid_parameters() {
    echo "Testing invalid parameters..."
    if $TEST_SCRIPT --invalid-param 2>/dev/null; then
        echo "✗ Should reject invalid parameters"
        return 1
    else
        echo "✓ Properly rejects invalid parameters"
        return 0
    fi
}

test_test_mode() {
    echo "Testing test mode..."
    if sudo $TEST_SCRIPT --test >/dev/null 2>&1; then
        echo "✓ Test mode works"
        return 0
    else
        echo "✗ Test mode failed"
        return 1
    fi
}

# Run all tests
main() {
    echo "Running tests for $TEST_SCRIPT"
    
    test_help_display || exit 1
    test_invalid_parameters || exit 1
    test_test_mode || exit 1
    
    echo "All tests passed!"
}

main "$@"
```

### Boot-Time Testing

**Test scenarios to validate**:

1. **Root execution without login**:
```bash
# Test as root without login session
sudo -i bash -c '/path/to/script.sh --test'
```

2. **Network unavailability**:
```bash
# Disconnect network and test retry logic
sudo iptables -A OUTPUT -j DROP
sudo ./script.sh --test
sudo iptables -F
```

3. **Concurrent execution prevention**:
```bash
# Start script in background and test lock
sudo ./script.sh --test &
sleep 1
sudo ./script.sh --test  # Should fail with lock error
```

4. **Service integration**:
```bash
# Test systemd service execution
sudo systemctl daemon-reload
sudo systemctl start test-service
sudo systemctl status test-service
sudo journalctl -u test-service
```

## Documentation Requirements

### Script Header Documentation

**Every script must include comprehensive header**:
```bash
#!/bin/bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING (if applicable)
# ====================================================================
# Script: script-name.sh - Brief one-line description
# Usage: ./script-name.sh [--param1 VALUE] [--param2] [--test]
# Boot-safe: Can run without user login, designed for system startup
# Author: Your Name | Date: YYYY-MM-DD
#
# Description:
#   Detailed description of what this script does, including:
#   - Primary objective and scope
#   - Key dependencies and requirements  
#   - Boot-time behavior and constraints
#   - Network dependencies and retry logic
#
# Parameters:
#   --param1 VALUE    Description of parameter 1
#   --param2          Description of parameter 2 (flag)
#   --test            Test mode - validate configuration without changes
#   --help            Display usage information
#
# Examples:
#   ./script-name.sh                           # Use defaults
#   ./script-name.sh --param1 value --param2  # Custom parameters
#   ./script-name.sh --test                    # Test mode
#
# Boot Integration:
#   systemctl enable script-name.service
#   systemctl start script-name.service
#
# Logs:
#   /var/log/zabbix-scripts/script-name-YYYYMMDD.log
#   journalctl -u script-name.service
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid parameters
#   3 - Network timeout
# ====================================================================
```

### Inline Documentation

**Document complex logic**:
```bash
# Install Zabbix repository based on detected OS
# Supports RHEL/CentOS 8+, Ubuntu 20.04+, Debian 10+
install_zabbix_repo() {
    local os_type="$1"
    
    log_info "Installing Zabbix repository for $os_type"
    
    case "$os_type" in
        "rhel")
            # Use RPM package for RHEL/CentOS
            # Note: Version 8+ required for systemd compatibility
            rpm -Uvh "https://repo.zabbix.com/..." || {
                log_error "Failed to install Zabbix repository for RHEL"
                return 1
            }
            ;;
        # ... other cases
    esac
}
```

## Common Patterns

### Configuration Management

**Embedded configuration pattern**:
```bash
# ====================================================================
# EMBEDDED CONFIGURATION (no external config files)
# ====================================================================
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"

# Service-specific configuration
readonly SERVICE_NAME="my-service"
readonly SERVICE_PORT="8080"
readonly CONFIG_FILE="/etc/my-service/config.conf"
readonly DEFAULT_TIMEOUT=30

# Network configuration
readonly DEFAULT_SERVER="server.example.com"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=10
```

### Service Management

**Service installation and configuration pattern**:
```bash
install_and_configure_service() {
    local server="$1"
    local port="$2"
    
    log_info "Installing $SERVICE_NAME"
    
    # Install package
    install_package "$SERVICE_NAME" || return 1
    
    # Backup existing configuration
    backup_configuration || return 1
    
    # Create new configuration
    create_configuration "$server" "$port" || return 1
    
    # Start and enable service
    start_and_enable_service || return 1
    
    # Validate installation
    validate_service_installation || return 1
    
    log_info "$SERVICE_NAME installation completed successfully"
    return 0
}
```

### Validation Pattern

**Comprehensive validation pattern**:
```bash
validate_installation() {
    local server="$1"
    
    log_info "Validating installation"
    
    # Check service status
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service is not running"
        return 1
    fi
    
    # Check port availability
    if ! netstat -tuln 2>/dev/null | grep -q ":$SERVICE_PORT "; then
        log_error "$SERVICE_NAME is not listening on port $SERVICE_PORT"
        return 1
    fi
    
    # Check configuration file
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file $CONFIG_FILE not found"
        return 1
    fi
    
    # Test network connectivity (if available)
    if ping -c 1 -W 5 "$server" >/dev/null 2>&1; then
        log_info "Network connectivity to $server confirmed"
    else
        log_warn "Cannot test connectivity to $server (network may be unavailable)"
    fi
    
    log_info "Installation validation completed successfully"
    return 0
}
```

## Quality Checklist

**Before committing any script, verify**:

- [ ] **Template Warning**: Clear "TEMPLATE SCRIPT" header if applicable
- [ ] **Configuration**: All placeholder values updated for specific use case
- [ ] **Dependencies**: No external files, libraries, or shared functions required
- [ ] **Logging**: All operations logged with appropriate levels
- [ ] **Error Handling**: Comprehensive error handling with meaningful messages
- [ ] **Network Retry**: Network operations include retry logic with exponential backoff
- [ ] **Lock Files**: Concurrent execution prevention implemented
- [ ] **Test Mode**: `--test` flag for validation without changes
- [ ] **Help Text**: Comprehensive help with examples and boot integration
- [ ] **Exit Codes**: Standard exit codes (0=success, 1=error, 2=invalid input, 3=network)
- [ ] **Boot Safety**: Can execute as root without login during system startup
- [ ] **Documentation**: Complete header documentation and inline comments
- [ ] **Test Script**: Corresponding test script created and validated
- [ ] **Recovery**: Backup and recovery procedures for all modifications

## Debugging Guidelines

### Log Analysis

**Log structure understanding**:
```
[2025-07-21 10:30:15] [INFO] [script-name] Normal operation message
[2025-07-21 10:30:16] [WARN] [script-name] Non-critical issue warning
[2025-07-21 10:30:17] [ERROR] [script-name] Critical failure message
```

**Common debugging commands**:
```bash
# Monitor script execution real-time
sudo tail -f /var/log/zabbix-scripts/script-name-$(date +%Y%m%d).log

# Find all errors from today
sudo grep "$(date +%Y-%m-%d)" /var/log/zabbix-scripts/*.log | grep "ERROR"

# Check systemd service logs
sudo journalctl -u service-name -n 50 -f

# Analyze network retry attempts
sudo grep "Network.*attempt" /var/log/zabbix-scripts/*.log
```

### Common Issues

**Lock file problems**:
```bash
# Check for stale lock files
sudo ls -la /var/run/*-script-name.pid
sudo ps aux | grep script-name  # Verify process not running
sudo rm /var/run/script-name.pid  # Remove if stale
```

**Permission issues**:
```bash
# Ensure proper permissions
sudo chown root:root /var/log/zabbix-scripts/
sudo chmod 755 /var/log/zabbix-scripts/
sudo chmod +x scripts/*.sh
```

**Network timeout issues**:
```bash
# Test network connectivity manually
ping -c 3 target-server
nslookup target-server
telnet target-server port

# Check retry logic configuration
grep -n "MAX_RETRIES\|RETRY_DELAY" scripts/script-name.sh
```

---

Remember: Every script is a complete, standalone solution designed for unattended execution in boot-time environments. Consistency, reliability, and comprehensive logging are more important than clever code.
