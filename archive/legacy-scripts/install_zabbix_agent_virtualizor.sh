#!/bin/bash
# ====================================================================
# Script: install_zabbix_agent_virtualizor.sh - Zabbix Agent Installation for Virtualizor Provisioning
# Usage: ./install_zabbix_agent_virtualizor.sh [--server IP] [--version VERSION] [--test]
# Virtualizor-ready: Designed for automated server provisioning
# Author: System Admin | Date: 2025-07-21
# ====================================================================

set -euo pipefail  # Exit on errors, undefined vars, pipe failures

# ====================================================================
# EMBEDDED CONFIGURATION (no external config files)
# ====================================================================
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME}.pid"

# Default configuration - modify these values as needed
readonly DEFAULT_ZABBIX_VERSION="6.4"
readonly DEFAULT_ZABBIX_SERVER="127.0.0.1"
readonly DEFAULT_ZABBIX_HOSTNAME="$(hostname)"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30
readonly NETWORK_TIMEOUT=60

# ====================================================================
# EMBEDDED LOGGING FUNCTIONS (no external dependencies)
# ====================================================================
setup_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] [$SCRIPT_NAME] $message"
}

log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_debug() { log_message "DEBUG" "$1"; }

# ====================================================================
# EMBEDDED UTILITY FUNCTIONS
# ====================================================================
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

cleanup() {
    local exit_code=$?
    log_info "Starting cleanup process"
    rm -f "$LOCK_FILE" 2>/dev/null || true
    if [ $exit_code -eq 0 ]; then
        log_info "Script completed successfully"
    else
        log_error "Script exited with error code $exit_code"
    fi
    exit $exit_code
}

validate_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 2
    fi
}

detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "/etc/os-release not found - unsupported OS"
        exit 2
    fi
    
    . /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            OS_FAMILY="debian"
            OS_ID="$ID"
            OS_VERSION="$VERSION_ID"
            ;;
        rhel|centos|almalinux|rocky)
            OS_FAMILY="rhel"
            OS_ID="$ID"
            OS_VERSION="${VERSION_ID%%.*}"
            ;;
        *)
            log_error "Unsupported OS: $ID"
            exit 2
            ;;
    esac
    
    log_info "Detected OS: $OS_ID $OS_VERSION (family: $OS_FAMILY)"
}

check_network_connectivity() {
    local url="$1"
    local description="$2"
    
    log_info "Testing network connectivity to $description"
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        if curl -s --connect-timeout $NETWORK_TIMEOUT --head "$url" >/dev/null 2>&1 ||
           wget -q --timeout=$NETWORK_TIMEOUT --spider "$url" 2>/dev/null; then
            log_info "Network connectivity confirmed to $description"
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Network connectivity failed (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "Failed to establish network connectivity to $description after $MAX_RETRIES attempts"
    return 3
}

validate_zabbix_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid Zabbix version format: $version (expected: X.Y)"
        return 1
    fi
    log_info "Zabbix version validation passed: $version"
    return 0
}

validate_server_address() {
    local server="$1"
    # Basic IP/hostname validation
    if [[ "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
       [[ "$server" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] ||
       [[ "$server" = "127.0.0.1" ]] ||
       [[ "$server" = "localhost" ]]; then
        log_info "Server address validation passed: $server"
        return 0
    else
        log_error "Invalid server address format: $server"
        return 1
    fi
}

install_zabbix_agent_debian() {
    local zabbix_version="$1"
    local repo_url="https://repo.zabbix.com/zabbix/${zabbix_version}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${zabbix_version}-1+ubuntu${OS_VERSION}_all.deb"
    local temp_deb="/tmp/zabbix-release.deb"
    
    log_info "Installing Zabbix agent on Debian/Ubuntu system"
    
    # Check network connectivity to Zabbix repository
    check_network_connectivity "$repo_url" "Zabbix repository" || return 3
    
    # Download with retries
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "Downloading Zabbix release package (attempt $attempt/$MAX_RETRIES)"
        
        if wget -q --timeout=$NETWORK_TIMEOUT "$repo_url" -O "$temp_deb"; then
            log_info "Zabbix release package downloaded successfully"
            break
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Download failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            log_error "Failed to download Zabbix release package after $MAX_RETRIES attempts"
            return 3
        fi
    done
    
    # Install release package
    if dpkg -i "$temp_deb" 2>/dev/null || {
        log_warn "Initial dpkg install failed, attempting to fix dependencies"
        apt-get update -qq && apt-get install -f -y
    }; then
        log_info "Zabbix release package installed successfully"
    else
        log_error "Failed to install Zabbix release package"
        return 1
    fi
    
    # Update package lists with retries
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "Updating package lists (attempt $attempt/$MAX_RETRIES)"
        
        if apt-get update -qq; then
            log_info "Package lists updated successfully"
            break
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Package update failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            log_error "Failed to update package lists after $MAX_RETRIES attempts"
            return 3
        fi
    done
    
    # Install Zabbix agent with retries
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "Installing Zabbix agent (attempt $attempt/$MAX_RETRIES)"
        
        if DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-agent; then
            log_info "Zabbix agent installed successfully"
            rm -f "$temp_deb"
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Zabbix agent installation failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            log_error "Failed to install Zabbix agent after $MAX_RETRIES attempts"
            rm -f "$temp_deb"
            return 1
        fi
    done
}

install_zabbix_agent_rhel() {
    local zabbix_version="$1"
    local repo_url="https://repo.zabbix.com/zabbix/${zabbix_version}/rhel/${OS_VERSION}/x86_64/zabbix-release-${zabbix_version}-1.el${OS_VERSION}.noarch.rpm"
    
    log_info "Installing Zabbix agent on RHEL/CentOS/AlmaLinux system"
    
    # Check network connectivity to Zabbix repository
    check_network_connectivity "$repo_url" "Zabbix repository" || return 3
    
    # Install release package with retries
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "Installing Zabbix release package (attempt $attempt/$MAX_RETRIES)"
        
        if rpm -Uvh --quiet "$repo_url"; then
            log_info "Zabbix release package installed successfully"
            break
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Release package installation failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            log_error "Failed to install Zabbix release package after $MAX_RETRIES attempts"
            return 3
        fi
    done
    
    # Install Zabbix agent with retries
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "Installing Zabbix agent (attempt $attempt/$MAX_RETRIES)"
        
        # Try dnf first, fall back to yum
        if command -v dnf >/dev/null 2>&1; then
            if dnf install -y -q zabbix-agent; then
                log_info "Zabbix agent installed successfully via dnf"
                return 0
            fi
        elif command -v yum >/dev/null 2>&1; then
            if yum install -y -q zabbix-agent; then
                log_info "Zabbix agent installed successfully via yum"
                return 0
            fi
        else
            log_error "No package manager found (dnf/yum)"
            return 2
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "Zabbix agent installation failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            log_error "Failed to install Zabbix agent after $MAX_RETRIES attempts"
            return 1
        fi
    done
}

configure_zabbix_agent() {
    local zabbix_server="$1"
    local zabbix_hostname="$2"
    local zbx_conf="/etc/zabbix/zabbix_agentd.conf"
    
    log_info "Configuring Zabbix agent"
    
    # Validate configuration file exists
    if [ ! -f "$zbx_conf" ]; then
        log_error "Zabbix agent configuration file not found: $zbx_conf"
        return 1
    fi
    
    # Backup original configuration
    local backup_conf="${zbx_conf}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$zbx_conf" "$backup_conf"; then
        log_error "Failed to create backup of configuration file"
        return 1
    fi
    log_info "Configuration backup created: $backup_conf"
    
    # Configure server settings
    log_info "Setting Zabbix server to: $zabbix_server"
    if ! sed -i "s/^Server=.*/Server=${zabbix_server}/" "$zbx_conf"; then
        log_error "Failed to update Server setting"
        return 1
    fi
    
    if ! sed -i "s/^ServerActive=.*/ServerActive=${zabbix_server}/" "$zbx_conf"; then
        log_error "Failed to update ServerActive setting"
        return 1
    fi
    
    if ! sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" "$zbx_conf"; then
        log_error "Failed to update Hostname setting"
        return 1
    fi
    
    # Enable debug logging for troubleshooting
    log_info "Enabling debug logging"
    if grep -q "^# DebugLevel=" "$zbx_conf"; then
        sed -i "s/^# DebugLevel=.*/DebugLevel=4/" "$zbx_conf"
    elif grep -q "^DebugLevel=" "$zbx_conf"; then
        sed -i "s/^DebugLevel=.*/DebugLevel=4/" "$zbx_conf"
    else
        echo "DebugLevel=4" >> "$zbx_conf"
    fi
    
    # Validate configuration
    if ! zabbix_agentd -t -c "$zbx_conf" >/dev/null 2>&1; then
        log_error "Zabbix agent configuration validation failed"
        log_info "Restoring backup configuration"
        cp "$backup_conf" "$zbx_conf" || true
        return 1
    fi
    
    log_info "Zabbix agent configuration validation passed"
    
    # Enable and start service
    log_info "Enabling and starting Zabbix agent service"
    if ! systemctl enable zabbix-agent; then
        log_error "Failed to enable Zabbix agent service"
        return 1
    fi
    
    if ! systemctl restart zabbix-agent; then
        log_error "Failed to restart Zabbix agent service"
        return 1
    fi
    
    # Wait for service to start and verify status
    sleep 3
    if ! systemctl is-active zabbix-agent >/dev/null 2>&1; then
        log_error "Zabbix agent service is not running"
        systemctl status zabbix-agent --no-pager || true
        return 1
    fi
    
    log_info "Zabbix agent service is running successfully"
    return 0
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Zabbix Agent Installation for Virtualizor Provisioning

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --server ADDRESS       Zabbix server address (default: $DEFAULT_ZABBIX_SERVER)
    --version VERSION      Zabbix version to install (default: $DEFAULT_ZABBIX_VERSION)
    --hostname NAME        Agent hostname (default: system hostname)
    --test                 Test mode - validate configuration without installing
    --help                 Show this help message

EXAMPLES:
    $0                                           # Use defaults
    $0 --server 192.168.1.100                  # Custom server
    $0 --server zabbix.company.com --version 7.0 # Custom server and version
    $0 --test                                   # Test mode

VIRTUALIZOR INTEGRATION:
    This script is designed for execution during server provisioning.
    It handles network instability, package repository issues, and
    provides comprehensive logging for troubleshooting.

LOGS:
    Installation logs: $LOG_FILE
    Service status: systemctl status zabbix-agent

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local zabbix_server="$DEFAULT_ZABBIX_SERVER"
    local zabbix_version="$DEFAULT_ZABBIX_VERSION"
    local zabbix_hostname="$DEFAULT_ZABBIX_HOSTNAME"
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server)
                zabbix_server="$2"
                shift 2
                ;;
            --version)
                zabbix_version="$2"
                shift 2
                ;;
            --hostname)
                zabbix_hostname="$2"
                shift 2
                ;;
            --test)
                test_mode=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_help
                exit 2
                ;;
        esac
    done
    
    # Setup and validation
    setup_logging
    log_info "Starting Zabbix agent installation"
    log_info "Parameters: Server=$zabbix_server, Version=$zabbix_version, Hostname=$zabbix_hostname"
    
    validate_root
    create_lock_file
    trap cleanup EXIT
    
    detect_os
    validate_zabbix_version "$zabbix_version" || exit 2
    validate_server_address "$zabbix_server" || exit 2
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        log_info "OS detected: $OS_ID $OS_VERSION ($OS_FAMILY)"
        log_info "Zabbix version: $zabbix_version"
        log_info "Zabbix server: $zabbix_server"
        log_info "Agent hostname: $zabbix_hostname"
        log_info "Test mode completed successfully"
        exit 0
    fi
    
    # Check if Zabbix agent is already installed and configured
    if systemctl is-active zabbix-agent >/dev/null 2>&1 && 
       grep -q "^Server=${zabbix_server}" /etc/zabbix/zabbix_agentd.conf 2>/dev/null; then
        log_info "Zabbix agent is already installed and configured correctly"
        log_info "Installation completed successfully (idempotent)"
        exit 0
    fi
    
    # Install Zabbix agent based on OS family
    case "$OS_FAMILY" in
        debian)
            install_zabbix_agent_debian "$zabbix_version" || exit $?
            ;;
        rhel)
            install_zabbix_agent_rhel "$zabbix_version" || exit $?
            ;;
        *)
            log_error "Unsupported OS family: $OS_FAMILY"
            exit 2
            ;;
    esac
    
    # Configure Zabbix agent
    configure_zabbix_agent "$zabbix_server" "$zabbix_hostname" || exit $?
    
    log_info "Zabbix agent installation and configuration completed successfully"
}

# Execute main function with all arguments
main "$@"