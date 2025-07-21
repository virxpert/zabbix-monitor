#!/bin/bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING
# ====================================================================
# This is a REFERENCE TEMPLATE demonstrating proper script structure
# DO NOT use as-is - customize configuration and logic for your needs
# Review existing scripts in /scripts/ before creating new ones
# ====================================================================
# Script: install-zabbix-agent.sh - Complete Zabbix agent installation and configuration
# Usage: ./install-zabbix-agent.sh [--server IP] [--hostname NAME] [--test]
# Boot-safe: Can run without user login, designed for system startup
# Author: System Admin | Date: 2025-07-21

set -euo pipefail  # Exit on errors, undefined vars, pipe failures

# ====================================================================
# EMBEDDED CONFIGURATION (no external config files)
# ====================================================================
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME}.pid"

# Default configuration - modify these values as needed
readonly DEFAULT_ZABBIX_SERVER="192.168.1.100"
readonly DEFAULT_HOSTNAME="$(hostname -f)"
readonly ZABBIX_VERSION="6.0"
readonly ZABBIX_PORT="10050"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=10

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

check_network_connectivity() {
    local server="$1"
    local retries=0
    
    log_info "Checking network connectivity to $server"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if ping -c 1 -W 5 "$server" >/dev/null 2>&1; then
            log_info "Network connectivity confirmed to $server"
            return 0
        fi
        
        retries=$((retries + 1))
        local delay=$((RETRY_DELAY * retries))
        log_warn "Network connectivity failed (attempt $retries/$MAX_RETRIES). Retrying in ${delay}s..."
        sleep $delay
    done
    
    log_error "Failed to establish network connectivity to $server after $MAX_RETRIES attempts"
    return 3
}

detect_os() {
    if [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/ubuntu_release ] || grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        echo "ubuntu"
    else
        echo "unknown"
    fi
}

install_zabbix_repo() {
    local os_type="$1"
    
    log_info "Installing Zabbix repository for $os_type"
    
    case "$os_type" in
        "rhel")
            rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/8/x86_64/zabbix-release-${ZABBIX_VERSION}-4.el8.noarch.rpm" 2>/dev/null || {
                log_error "Failed to install Zabbix repository for RHEL"
                return 1
            }
            ;;
        "ubuntu"|"debian")
            wget -q "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu20.04_all.deb" -O /tmp/zabbix-release.deb || {
                log_error "Failed to download Zabbix repository package"
                return 1
            }
            dpkg -i /tmp/zabbix-release.deb >/dev/null 2>&1 || {
                log_error "Failed to install Zabbix repository"
                return 1
            }
            apt-get update >/dev/null 2>&1
            ;;
        *)
            log_error "Unsupported operating system: $os_type"
            return 1
            ;;
    esac
    
    log_info "Zabbix repository installed successfully"
    return 0
}

install_zabbix_agent() {
    local os_type="$1"
    
    log_info "Installing Zabbix agent for $os_type"
    
    case "$os_type" in
        "rhel")
            yum install -y zabbix-agent2 >/dev/null 2>&1 || {
                log_error "Failed to install Zabbix agent"
                return 1
            }
            ;;
        "ubuntu"|"debian")
            apt-get install -y zabbix-agent2 >/dev/null 2>&1 || {
                log_error "Failed to install Zabbix agent"
                return 1
            }
            ;;
        *)
            log_error "Unsupported operating system: $os_type"
            return 1
            ;;
    esac
    
    log_info "Zabbix agent installed successfully"
    return 0
}

configure_zabbix_agent() {
    local server="$1"
    local hostname="$2"
    local config_file="/etc/zabbix/zabbix_agent2.conf"
    
    log_info "Configuring Zabbix agent (Server: $server, Hostname: $hostname)"
    
    # Backup original config
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Original configuration backed up"
    fi
    
    # Create new configuration
    cat > "$config_file" << EOF
# Zabbix Agent Configuration
# Generated by $SCRIPT_NAME on $(date)

PidFile=/var/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10

Server=$server
ServerActive=$server
Hostname=$hostname
ListenPort=$ZABBIX_PORT

# Enable remote commands (use with caution)
EnableRemoteCommands=1

# Timeout settings
Timeout=30
Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOF

    log_info "Zabbix agent configuration completed"
    return 0
}

start_and_enable_service() {
    log_info "Starting and enabling Zabbix agent service"
    
    systemctl daemon-reload 2>/dev/null || {
        log_error "Failed to reload systemd daemon"
        return 1
    }
    
    systemctl enable zabbix-agent2 2>/dev/null || {
        log_error "Failed to enable Zabbix agent service"
        return 1
    }
    
    systemctl start zabbix-agent2 2>/dev/null || {
        log_error "Failed to start Zabbix agent service"
        return 1
    }
    
    # Wait for service to fully start
    sleep 5
    
    if systemctl is-active --quiet zabbix-agent2; then
        log_info "Zabbix agent service is running successfully"
        return 0
    else
        log_error "Zabbix agent service failed to start properly"
        return 1
    fi
}

validate_installation() {
    local server="$1"
    
    log_info "Validating Zabbix agent installation"
    
    # Check if service is running
    if ! systemctl is-active --quiet zabbix-agent2; then
        log_error "Zabbix agent service is not running"
        return 1
    fi
    
    # Check if port is listening
    if ! netstat -tuln 2>/dev/null | grep -q ":$ZABBIX_PORT "; then
        log_error "Zabbix agent is not listening on port $ZABBIX_PORT"
        return 1
    fi
    
    # Test connectivity to server (if network available)
    if ping -c 1 -W 5 "$server" >/dev/null 2>&1; then
        log_info "Network connectivity to Zabbix server confirmed"
    else
        log_warn "Cannot test connectivity to Zabbix server (network may be unavailable)"
    fi
    
    log_info "Zabbix agent installation validation completed successfully"
    return 0
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Complete Zabbix agent installation and configuration

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --server IP         Zabbix server IP address (default: $DEFAULT_ZABBIX_SERVER)
    --hostname NAME     Agent hostname (default: $DEFAULT_HOSTNAME)
    --test              Test mode - validate but don't install
    --help              Show this help message

EXAMPLES:
    $0                                          # Use defaults
    $0 --server 192.168.1.50 --hostname web01  # Custom server and hostname
    $0 --test                                   # Test mode only

BOOT INTEGRATION:
    # Add to /etc/systemd/system/install-zabbix.service
    [Unit]
    Description=Install Zabbix Agent
    After=network.target
    
    [Service]
    Type=oneshot
    ExecStart=$PWD/$0
    RemainAfterExit=yes
    
    [Install]
    WantedBy=multi-user.target

LOGS:
    All output is logged to: $LOG_FILE
    Service logs: journalctl -u install-zabbix

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local zabbix_server="$DEFAULT_ZABBIX_SERVER"
    local hostname="$DEFAULT_HOSTNAME"
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server)
                zabbix_server="$2"
                shift 2
                ;;
            --hostname)
                hostname="$2"
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
    log_info "Starting Zabbix agent installation process"
    log_info "Parameters: Server=$zabbix_server, Hostname=$hostname, Test=$test_mode"
    
    validate_root
    create_lock_file
    trap cleanup EXIT
    
    # Detect operating system
    local os_type=$(detect_os)
    if [ "$os_type" == "unknown" ]; then
        log_error "Unsupported operating system"
        exit 2
    fi
    log_info "Detected operating system: $os_type"
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        check_network_connectivity "$zabbix_server" || true
        log_info "Test mode completed"
        exit 0
    fi
    
    # Full installation process
    log_info "Beginning full installation process"
    
    # Network connectivity check (with retries)
    check_network_connectivity "$zabbix_server" || {
        log_error "Cannot proceed without network connectivity"
        exit 3
    }
    
    # Installation steps
    install_zabbix_repo "$os_type" || exit 1
    install_zabbix_agent "$os_type" || exit 1
    configure_zabbix_agent "$zabbix_server" "$hostname" || exit 1
    start_and_enable_service || exit 1
    validate_installation "$zabbix_server" || exit 1
    
    log_info "Zabbix agent installation completed successfully"
    log_info "Agent configured for server: $zabbix_server"
    log_info "Agent hostname: $hostname"
    log_info "Service status: $(systemctl is-active zabbix-agent2)"
}

# Execute main function with all arguments
main "$@"
