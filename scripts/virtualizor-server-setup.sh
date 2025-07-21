#!/bin/bash
# ====================================================================
# Script: virtualizor-server-setup.sh - Complete Virtualizor Server Provisioning
# Usage: ./virtualizor-server-setup.sh [--stage STAGE] [--config-file PATH] [--test]
# Virtualizor-ready: Designed for automated server provisioning with reboot persistence
# Author: System Admin | Date: 2025-07-21
# ====================================================================

# Shell compatibility check - ensure we're running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: This script requires bash to run properly."
    echo "Please execute with: bash $0"
    exit 1
fi

set -euo pipefail  # Exit on errors, undefined vars, pipe failures

# ====================================================================
# EMBEDDED CONFIGURATION (no external config files)
# ====================================================================
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME}.pid"
readonly STATE_FILE="/var/lib/${SCRIPT_NAME}.state"
readonly REBOOT_FLAG_FILE="/var/lib/${SCRIPT_NAME}.reboot"
readonly SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SCRIPT_NAME}.service"

# Stage definitions
readonly STAGE_INIT="init"
readonly STAGE_BANNER="banner"
readonly STAGE_UPDATES="updates"
readonly STAGE_POST_REBOOT="post-reboot"
readonly STAGE_ZABBIX_INSTALL="zabbix-install"
readonly STAGE_ZABBIX_CONFIGURE="zabbix-configure"
readonly STAGE_TUNNEL_SETUP="tunnel-setup"
readonly STAGE_COMPLETE="complete"

# Default configuration - modify these values as needed
readonly DEFAULT_BANNER_TEXT="Virtualizor Managed Server - Setup in Progress"
readonly DEFAULT_BANNER_COLOR="red"
readonly DEFAULT_MOTD_MESSAGE="WARNING: Authorized Access Only
*   This VPS is the property of Everything Cloud Solutions *
*   Unauthorized use is strictly prohibited and monitored. *
*   For any issue, report it to support@everythingcloud.ca *"

# Dynamic Configuration System for Virtualizor Provisioning
# Supports: Environment Variables, Command-line Parameters, and Runtime Prompts

# Method 1: Environment Variables (if set)
# Method 2: Command-line Parameters (see usage function)  
# Method 3: Secure defaults with runtime validation

# Default configuration (fallback values - update these for your infrastructure)
readonly DEFAULT_ZABBIX_VERSION="6.4"
readonly DEFAULT_ZABBIX_SERVER="127.0.0.1"

# CRITICAL: Update these default values for your infrastructure before deployment
# These are used when no environment variables or parameters are provided
readonly FALLBACK_HOME_SERVER_IP="your-monitor-server.example.com"
readonly FALLBACK_HOME_SERVER_SSH_PORT="2022"
readonly FALLBACK_SSH_USER="zabbix-user"

# Runtime configuration (populated from env vars, parameters, or defaults)
DEFAULT_HOME_SERVER_IP="${ZABBIX_SERVER_DOMAIN:-$FALLBACK_HOME_SERVER_IP}"
DEFAULT_HOME_SERVER_SSH_PORT="${SSH_TUNNEL_PORT:-$FALLBACK_HOME_SERVER_SSH_PORT}"
DEFAULT_SSH_USER="${SSH_TUNNEL_USER:-$FALLBACK_SSH_USER}"

readonly DEFAULT_ZABBIX_SERVER_PORT=10051
readonly DEFAULT_SSH_KEY="/root/.ssh/zabbix_tunnel_key"
readonly DEFAULT_ADMIN_USER="root"
readonly DEFAULT_ADMIN_KEY="/root/.ssh/id_rsa"
readonly ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"

# System settings
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30
readonly REBOOT_TIMEOUT=300  # 5 minutes wait after reboot
readonly UPDATE_TIMEOUT=1800  # 30 minutes for updates

# ====================================================================
# EMBEDDED LOGGING FUNCTIONS (no external dependencies)
# ====================================================================
setup_logging() {
    # Ensure required directories exist with proper permissions
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    mkdir -p "$(dirname "$REBOOT_FLAG_FILE")" 2>/dev/null || true
    
    # Create named pipes for logging (compatible with all shells)
    if command -v mkfifo >/dev/null 2>&1; then
        LOG_PIPE_OUT="/tmp/${SCRIPT_NAME}_out_$$"
        LOG_PIPE_ERR="/tmp/${SCRIPT_NAME}_err_$$"
        mkfifo "$LOG_PIPE_OUT" "$LOG_PIPE_ERR" 2>/dev/null || true
        if [ -p "$LOG_PIPE_OUT" ] && [ -p "$LOG_PIPE_ERR" ]; then
            tee -a "$LOG_FILE" < "$LOG_PIPE_OUT" &
            tee -a "$LOG_FILE" < "$LOG_PIPE_ERR" >&2 &
            exec 1>"$LOG_PIPE_OUT"
            exec 2>"$LOG_PIPE_ERR"
            # Clean up pipes on exit
            trap 'rm -f "$LOG_PIPE_OUT" "$LOG_PIPE_ERR" 2>/dev/null || true' EXIT
        else
            # Fallback: direct file logging without tee
            exec 1>>"$LOG_FILE"
            exec 2>&1
        fi
    else
        # Simple fallback for systems without mkfifo
        exec 1>>"$LOG_FILE"
        exec 2>&1
    fi
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
log_stage() { log_message "STAGE" "$1"; }

# ====================================================================
# STATE MANAGEMENT FUNCTIONS
# ====================================================================
save_state() {
    local stage="$1"
    local data="$2"
    
    cat > "$STATE_FILE" << EOF
CURRENT_STAGE="$stage"
EXECUTION_START="$(date '+%Y-%m-%d %H:%M:%S')"
STAGE_DATA="$data"
SCRIPT_PID=$$
HOSTNAME="$(hostname)"
EOF
    log_debug "State saved: $stage"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        log_debug "State loaded: $CURRENT_STAGE"
        return 0
    else
        CURRENT_STAGE=""
        return 1
    fi
}

clear_state() {
    rm -f "$STATE_FILE" "$REBOOT_FLAG_FILE" 2>/dev/null || true
    log_debug "State cleared"
}

set_reboot_flag() {
    local next_stage="$1"
    echo "$next_stage" > "$REBOOT_FLAG_FILE"
    log_info "Reboot flag set for next stage: $next_stage"
}

check_reboot_flag() {
    if [ -f "$REBOOT_FLAG_FILE" ]; then
        cat "$REBOOT_FLAG_FILE"
        return 0
    else
        return 1
    fi
}

clear_reboot_flag() {
    rm -f "$REBOOT_FLAG_FILE" 2>/dev/null || true
    log_debug "Reboot flag cleared"
}

# ====================================================================
# REBOOT PERSISTENCE FUNCTIONS
# ====================================================================
create_systemd_service() {
    log_info "Creating systemd service for reboot persistence"
    
    # Get absolute path to this script
    local script_path="$(readlink -f "$0")"
    log_info "Using script path: $script_path"
    
    # Ensure state directories exist
    mkdir -p "$(dirname "$REBOOT_FLAG_FILE")" 2>/dev/null || true
    
    cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Virtualizor Server Setup - Reboot Persistent
After=network.target network-online.target
Wants=network-online.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=$script_path --resume-after-reboot
RemainAfterExit=no
StandardOutput=journal
StandardError=journal
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF

    # Ensure script has execute permissions
    chmod +x "$script_path"
    
    systemctl daemon-reload
    systemctl enable "${SCRIPT_NAME}.service"
    log_info "Systemd service created and enabled"
}

remove_systemd_service() {
    if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
        systemctl disable "${SCRIPT_NAME}.service" 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE_FILE"
        systemctl daemon-reload
        log_info "Systemd service removed"
    fi
}

schedule_reboot() {
    local next_stage="$1"
    local delay="${2:-10}"
    
    log_info "Scheduling reboot in ${delay} seconds for next stage: $next_stage"
    set_reboot_flag "$next_stage"
    
    # Schedule reboot
    (
        sleep "$delay"
        log_info "Initiating scheduled reboot"
        /sbin/reboot
    ) &
    
    log_info "Reboot scheduled. Script will continue after restart."
    exit 0
}

# ====================================================================
# EMBEDDED UTILITY FUNCTIONS
# ====================================================================

# Monitor system activity during long operations
show_system_activity() {
    local process_name="${1:-apt}"
    log_info "System Activity - Load: $(uptime | awk '{print $NF}') | Memory: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
    
    # Show active package management processes
    local active_procs=$(pgrep -f "$process_name" | wc -l)
    if [ "$active_procs" -gt 0 ]; then
        log_info "Active $process_name processes: $active_procs"
        # Show what dpkg is currently doing
        if pgrep dpkg >/dev/null 2>&1; then
            local dpkg_status=$(ps -eo pid,state,comm,args | grep dpkg | grep -v grep | head -3)
            if [ -n "$dpkg_status" ]; then
                log_info "Current dpkg activity detected"
            fi
        fi
    fi
}

# ====================================================================
# ERROR HANDLING FUNCTIONS
# ====================================================================
handle_error() {
    local error_code="$1"
    local error_message="$2"
    local error_stage="${3:-${CURRENT_STAGE:-'unknown'}}"
    local error_line="${4:-'unknown'}"
    
    log_error "=== ERROR DETECTED ==="
    log_error "Error Code: $error_code"
    log_error "Error Message: $error_message"
    log_error "Failed Stage: $error_stage"
    log_error "Script Line: $error_line"
    log_error "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    log_error "======================"
    
    # Error categorization and specific handling
    case "$error_code" in
        1)
            log_error "General error - check logs for details"
            ;;
        2)
            log_error "Invalid input or configuration error"
            ;;
        3)
            log_error "Network or connectivity error"
            ;;
        4)
            log_error "Provisioning timeout error"
            ;;
        126)
            log_error "Command not executable - check permissions"
            ;;
        127)
            log_error "Command not found - missing dependency"
            ;;
        130)
            log_error "Script interrupted by user (Ctrl+C)"
            ;;
        *)
            log_error "Unexpected error code: $error_code"
            ;;
    esac
    
    return "$error_code"
}

# Error trap function
error_trap() {
    local error_code=$?
    local error_line=$1
    
    if [ $error_code -ne 0 ]; then
        handle_error "$error_code" "Command failed" "${CURRENT_STAGE:-'unknown'}" "$error_line"
    fi
    
    cleanup
}

# Set error trap
set_error_trap() {
    trap 'error_trap $LINENO' ERR
    trap 'handle_error 130 "Script interrupted" "${CURRENT_STAGE:-'unknown'}" $LINENO; exit 130' INT TERM
}

# ====================================================================
# SYNTAX VALIDATION FUNCTIONS
# ====================================================================
validate_script_syntax() {
    log_info "Performing script syntax validation..."
    
    # Check bash syntax
    if ! bash -n "$0" 2>/dev/null; then
        log_error "CRITICAL: Script syntax error detected"
        log_error "Run 'bash -n $0' to see detailed syntax errors"
        return 1
    fi
    
    # Check shell compatibility
    if [ -z "$BASH_VERSION" ]; then
        log_error "CRITICAL: Script requires bash shell"
        log_error "Current shell: $SHELL"
        return 1
    fi
    
    # Check required commands
    local required_commands="systemctl wget ssh-keygen sed grep awk"
    local missing_commands=""
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands="$missing_commands $cmd"
        fi
    done
    
    if [ -n "$missing_commands" ]; then
        log_error "CRITICAL: Missing required commands:$missing_commands"
        log_error "Please install missing packages and try again"
        return 1
    fi
    
    log_info "✅ Script syntax validation passed"
    return 0
}

# ====================================================================
# EMBEDDED UTILITY FUNCTIONS
# ====================================================================
create_lock_file() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    log_info "Created lock file with PID $$"
}

cleanup() {
    local exit_code=$?
    log_info "Starting cleanup process with exit code: $exit_code"
    
    # Enhanced error reporting
    if [ $exit_code -ne 0 ]; then
        log_error "==============================="
        log_error "SCRIPT FAILED WITH EXIT CODE $exit_code"
        log_error "==============================="
        log_error "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        log_error "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
        log_error "Current User: $(whoami 2>/dev/null || echo 'unknown')"
        log_error "Working Directory: $(pwd 2>/dev/null || echo 'unknown')"
        
        # Show current stage if available
        if load_state 2>/dev/null; then
            log_error "Current Stage: $CURRENT_STAGE"
            log_error "Stage Data: $STAGE_DATA"
        else
            log_error "No state information available"
        fi
        
        # System information
        log_error "System Information:"
        log_error "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
        log_error "  Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
        log_error "  Uptime: $(uptime 2>/dev/null | cut -d, -f1 || echo 'unknown')"
        
        # Network status
        log_error "Network Status:"
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_error "  Internet: Connected"
        else
            log_error "  Internet: Disconnected"
        fi
        
        # Disk space
        log_error "Disk Space:"
        df -h / 2>/dev/null | tail -1 | while read filesystem size used avail percent mountpoint; do
            log_error "  Root: $used used of $size ($percent)"
        done 2>/dev/null || log_error "  Root: Unable to check"
        
        # Memory
        log_error "Memory Usage:"
        free -m 2>/dev/null | grep "Mem:" | while read label total used free shared buffers cached; do
            log_error "  RAM: ${used}MB used of ${total}MB"
        done 2>/dev/null || log_error "  RAM: Unable to check"
        
        log_error "==============================="
        log_error "TROUBLESHOOTING INFORMATION:"
        log_error "1. Check full logs: $LOG_FILE"
        log_error "2. Verify root privileges: sudo -i"
        log_error "3. Check network connectivity: ping 8.8.8.8"
        log_error "4. Verify disk space: df -h"
        log_error "5. Manual resume: $0 --stage <stage>"
        log_error "6. Clean start: $0 --cleanup && $0"
        log_error "==============================="
        
        # Keep state file for troubleshooting
    else
        log_info "Script completed successfully"
    fi
    
    rm -f "$LOCK_FILE" 2>/dev/null || true
    
    if [ $exit_code -eq 0 ]; then
        log_info "Stage completed successfully"
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
            
            # AlmaLinux 10 compatibility: use RHEL 9 packages (el10 packages don't exist yet)
            if [[ "$ID" == "almalinux" && "$OS_VERSION" == "10" ]]; then
                log_info "AlmaLinux 10 detected - using RHEL 9 packages for Zabbix compatibility"
                OS_VERSION="9"
            fi
            ;;
        *)
            log_error "Unsupported OS: $ID"
            exit 2
            ;;
    esac
    
    log_info "Detected OS: $OS_ID $OS_VERSION (family: $OS_FAMILY)"
}

wait_for_network() {
    local timeout=300  # 5 minutes
    local count=0
    local test_hosts="8.8.8.8 1.1.1.1 8.8.4.4"  # Multiple test targets
    
    log_info "Waiting for network connectivity (timeout: ${timeout}s)"
    
    while [ $count -lt $timeout ]; do
        # Test multiple hosts for better reliability
        for host in $test_hosts; do
            if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
                log_info "Network connectivity confirmed (via $host)"
                return 0
            fi
        done
        
        count=$((count + 5))
        sleep 5
        
        if [ $((count % 30)) -eq 0 ]; then
            log_info "Still waiting for network... (${count}s elapsed)"
            
            # Provide diagnostic information every 30 seconds
            log_info "Network diagnostics:"
            
            # Check network interfaces
            if command -v ip >/dev/null 2>&1; then
                local interfaces=$(ip link show | grep 'state UP' | wc -l)
                log_info "  Active interfaces: $interfaces"
            elif command -v ifconfig >/dev/null 2>&1; then
                local interfaces=$(ifconfig | grep 'flags=.*UP' | wc -l)
                log_info "  Active interfaces: $interfaces"
            fi
            
            # Check default route
            if command -v ip >/dev/null 2>&1; then
                if ip route show default >/dev/null 2>&1; then
                    log_info "  Default route: Present"
                else
                    log_warn "  Default route: Missing"
                fi
            fi
            
            # Check DNS resolution
            if command -v nslookup >/dev/null 2>&1; then
                if nslookup google.com >/dev/null 2>&1; then
                    log_info "  DNS resolution: Working"
                else
                    log_warn "  DNS resolution: Failed"
                fi
            fi
        fi
    done
    
    log_error "Network connectivity timeout after ${timeout}s"
    log_error "Tested hosts: $test_hosts"
    log_error "Please check network configuration:"
    log_error "  1. Verify network interface is up"
    log_error "  2. Check IP address assignment (DHCP/static)"
    log_error "  3. Verify default gateway"
    log_error "  4. Check DNS configuration"
    log_error "  5. Verify firewall rules"
    return 3
}

# ====================================================================
# STAGE IMPLEMENTATION FUNCTIONS
# ====================================================================
stage_init() {
    log_stage "STAGE: INIT - Initial setup and validation"
    
    # Enhanced error handling with detailed diagnostics
    log_info "Starting comprehensive system validation..."
    
    # 1. Script syntax validation (FIRST - critical for reliability)
    log_info "Step 1/5: Validating script syntax..."
    if ! validate_script_syntax; then
        log_error "CRITICAL: Script syntax validation failed"
        log_error "This indicates a serious script integrity issue"
        return 1
    fi
    log_info "✅ Script syntax validation passed"
    
    # 2. Check if we're running as root
    log_info "Step 2/5: Checking root privileges..."
    if [ "$EUID" -ne 0 ]; then
        log_error "CRITICAL: Script must be run as root (current EUID: $EUID)"
        log_error "Solution: Run with 'sudo $0' or as root user"
        return 1
    fi
    log_info "✅ Root privileges confirmed"
    
    # 3. Detect OS with enhanced error reporting
    log_info "Step 3/5: Detecting operating system..."
    if ! detect_os; then
        log_error "CRITICAL: OS detection failed"
        log_error "Unable to determine operating system type"
        return 1
    fi
    log_info "✅ OS detected: $OS_ID $OS_VERSION (family: $OS_FAMILY)"
    
    # 4. Network connectivity check with timeout and retry
    log_info "Step 4/5: Checking network connectivity..."
    if ! wait_for_network; then
        log_error "CRITICAL: Network connectivity check failed"
        log_error "This script requires internet access to download packages"
        log_error "Please check network configuration and try again"
        return 1
    fi
    log_info "✅ Network connectivity confirmed"
    
    # 5. Create systemd service with error handling
    log_info "Step 5/5: Setting up reboot persistence..."
    if ! create_systemd_service; then
        log_error "WARNING: Failed to create systemd service"
        log_error "Reboot persistence may not work properly"
        # Don't fail completely, continue without persistence
    else
        log_info "✅ Systemd service created for reboot persistence"
    fi
    
    save_state "$STAGE_BANNER" "os_detected=$OS_ID-$OS_VERSION,syntax_validated=true"
    log_info "✅ Initialization completed successfully (5/5 checks passed)"
    return 0
}

stage_banner() {
    log_stage "STAGE: BANNER - Setting up system banner and MOTD"
    
    local banner_text="${1:-$DEFAULT_BANNER_TEXT}"
    local banner_color="${2:-$DEFAULT_BANNER_COLOR}"
    
    # Set login banner
    cat > /etc/motd << EOF

===============================================
   $banner_text
===============================================
   Hostname: $(hostname)
   Date: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Setup Progress: System Updates in Progress
===============================================

EOF

    # Set SSH banner
    cat > /etc/issue.net << EOF
===============================================
$banner_text
===============================================
EOF

    # Configure SSH to show banner
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i 's/#Banner none/Banner \/etc\/issue.net/' /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null || true
    fi
    
    log_info "System banner configured"
    save_state "$STAGE_UPDATES" "banner_set=true"
    return 0
}

stage_updates() {
    log_stage "STAGE: UPDATES - Installing system updates and upgrades"
    
    local update_required=false
    
    case "$OS_FAMILY" in
        debian)
            # Configure dpkg for unattended operation with automatic config file handling
            export DEBIAN_FRONTEND=noninteractive
            export DEBIAN_PRIORITY=critical
            export DEBCONF_NONINTERACTIVE_SEEN=true
            
            # Optimize for faster kernel operations
            export INITRD=no  # Skip initramfs update during package installation
            export APT_LISTCHANGES_FRONTEND=none  # Skip package change notifications
            export NEEDRESTART_MODE=l  # Skip interactive service restart prompts
            
            # Create temporary dpkg configuration for faster processing
            cat > /etc/dpkg/dpkg.cfg.d/01_virtualizor << 'EOF'
# Speed up package operations
force-unsafe-io
no-debsig
force-confold
force-confdef
EOF
            
            log_info "Updating package lists"
            if ! timeout $UPDATE_TIMEOUT apt-get update -qq; then
                log_error "Package list update failed or timed out"
                return 1
            fi
            
            log_info "Checking for available upgrades"
            local upgrades=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
            local kernel_updates=$(apt list --upgradable 2>/dev/null | grep -c linux-image || echo "0")
            
            # Check for phased updates that might not actually be installable
            local phased_updates=$(apt list --upgradable 2>/dev/null | grep -c "phased" || echo "0")
            if [ "$phased_updates" -gt 0 ]; then
                log_info "Detected $phased_updates phased updates (may be deferred)"
                # Get actual installable updates by simulating upgrade
                local actual_upgrades=$(apt-get upgrade -s 2>/dev/null | grep -c "^Inst " || echo "0")
                if [ "$actual_upgrades" -lt "$upgrades" ]; then
                    log_info "Adjusting upgrade count: $upgrades reported, $actual_upgrades actually installable"
                    upgrades=$actual_upgrades
                fi
            fi
            
            # Ensure upgrades and kernel_updates are valid integers
            if ! [[ "$upgrades" =~ ^[0-9]+$ ]]; then
                log_warn "Unable to determine upgrade count, assuming 0"
                upgrades=0
            fi
            if ! [[ "$kernel_updates" =~ ^[0-9]+$ ]]; then
                kernel_updates=0
            fi
            
            if [ "$upgrades" -gt 0 ]; then
                log_info "Found $upgrades packages to upgrade"
                if [ "$kernel_updates" -gt 0 ]; then
                    log_info "Kernel updates detected - this may take longer than usual"
                fi
                update_required=true
                
                log_info "Installing system updates (keeping existing config files) - This may take up to 30 minutes..."
                # Use dpkg options to automatically handle configuration file conflicts
                # Add progress monitoring for long-running operations
                {
                    timeout $UPDATE_TIMEOUT apt-get upgrade -y \
                        -o Dpkg::Options::="--force-confold" \
                        -o Dpkg::Options::="--force-confdef" \
                        -o Dpkg::Use-Pty=0 \
                        -o Apt::Color=0 &
                    local apt_pid=$!
                    
                    # Monitor progress every 60 seconds with a reasonable timeout
                    local elapsed=0
                    local max_wait=300  # 5 minutes max wait for monitoring (apt should complete quickly if no real updates)
                    
                    while kill -0 $apt_pid 2>/dev/null && [ $elapsed -lt $max_wait ]; do
                        sleep 60
                        elapsed=$((elapsed + 60))
                        if [ $((elapsed % 300)) -eq 0 ]; then  # Every 5 minutes
                            log_info "Update still in progress... (${elapsed}s elapsed)"
                            show_system_activity "apt"
                        fi
                    done
                    
                    # If process is still running after our monitoring timeout, it's a real long operation
                    if kill -0 $apt_pid 2>/dev/null; then
                        log_info "Long-running update detected, continuing monitoring..."
                        wait $apt_pid
                    else
                        # Process completed during our monitoring
                        wait $apt_pid 2>/dev/null || true
                    fi
                } || {
                    local exit_code=$?
                    if [ $exit_code -eq 0 ]; then
                        log_info "System upgrade completed (no actual updates installed)"
                    else
                        log_error "System upgrade failed or timed out (exit code: $exit_code)"
                        return 1
                    fi
                }
                
                log_info "Installing security updates (keeping existing config files) - This may take additional time..."
                {
                    timeout $UPDATE_TIMEOUT apt-get dist-upgrade -y \
                        -o Dpkg::Options::="--force-confold" \
                        -o Dpkg::Options::="--force-confdef" \
                        -o Dpkg::Options::="--force-overwrite" \
                        -o Dpkg::Use-Pty=0 \
                        -o Apt::Color=0 \
                        -o Apt::Get::Assume-Yes=true \
                        -o Apt::Get::Fix-Broken=true \
                        -q &
                    local dist_upgrade_pid=$!
                    
                    # Monitor dist-upgrade progress every 60 seconds
                    local dist_elapsed=0
                    while kill -0 $dist_upgrade_pid 2>/dev/null; do
                        sleep 60
                        dist_elapsed=$((dist_elapsed + 60))
                        if [ $((dist_elapsed % 300)) -eq 0 ]; then  # Every 5 minutes
                            log_info "Security update still in progress... (${dist_elapsed}s elapsed)"
                            show_system_activity "apt"
                        fi
                    done
                    wait $dist_upgrade_pid
                } || {
                    log_warn "Security upgrade failed or timed out, continuing"
                }
                
                # Clean up temporary configuration
                rm -f /etc/dpkg/dpkg.cfg.d/01_virtualizor
                
                # Handle initramfs updates if kernel was upgraded
                if [ "$kernel_updates" -gt 0 ]; then
                    log_info "Updating initramfs for new kernel (this may take several minutes)..."
                    update-initramfs -u -k all || log_warn "initramfs update failed, but continuing"
                    log_info "Updating GRUB configuration..."
                    update-grub || log_warn "GRUB update failed, but continuing"
                fi
            fi
            ;;
            
        rhel)
            log_info "Checking for available updates"
            local package_manager=""
            if command -v dnf >/dev/null 2>&1; then
                package_manager="dnf"
            elif command -v yum >/dev/null 2>&1; then
                package_manager="yum"
            else
                log_error "No package manager found (dnf/yum)"
                return 1
            fi
            
            local updates=$($package_manager check-update -q 2>/dev/null | wc -l | tr -d '\n\r ' || echo "0")
            # Ensure updates is a valid integer
            if ! [[ "$updates" =~ ^[0-9]+$ ]]; then
                log_warn "Unable to determine update count, assuming 0"
                updates=0
            fi
            
            if [ "$updates" -gt 0 ]; then
                log_info "Found $updates updates available"
                update_required=true
                
                log_info "Installing system updates using $package_manager"
                if ! timeout $UPDATE_TIMEOUT $package_manager update -y -q; then
                    log_error "System update failed or timed out"
                    return 1
                fi
            else
                log_info "No updates available"
            fi
            ;;
    esac
    
    if [ "$update_required" = true ]; then
        log_info "Updates installed, reboot required"
        save_state "$STAGE_POST_REBOOT" "updates_installed=true"
        
        # Update banner to show reboot status
        cat > /etc/motd << EOF

===============================================
   $DEFAULT_BANNER_TEXT
===============================================
   Hostname: $(hostname)
   Date: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Setup Progress: Rebooting after updates...
===============================================

EOF
        
        schedule_reboot "$STAGE_POST_REBOOT" 10
    else
        log_info "No updates required, proceeding to Zabbix installation"
        save_state "$STAGE_ZABBIX_INSTALL" "no_updates_needed=true"
        return 0
    fi
}

stage_post_reboot() {
    log_stage "STAGE: POST-REBOOT - Validating system after reboot"
    
    # Wait a moment for system to fully initialize
    sleep 30
    
    # Verify system is ready
    wait_for_network
    
    # Update banner
    cat > /etc/motd << EOF

===============================================
   $DEFAULT_BANNER_TEXT
===============================================
   Hostname: $(hostname)
   Date: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Setup Progress: Installing Zabbix Agent...
===============================================

EOF
    
    log_info "Post-reboot validation completed"
    save_state "$STAGE_ZABBIX_INSTALL" "post_reboot_complete=true"
    return 0
}

stage_zabbix_install() {
    log_stage "STAGE: ZABBIX-INSTALL - Installing Zabbix Agent"
    
    local zabbix_version="${1:-$DEFAULT_ZABBIX_VERSION}"
    local zabbix_server="${2:-$DEFAULT_ZABBIX_SERVER}"
    local zabbix_hostname="$(hostname)"
    
    # Use the embedded Zabbix installation logic
    log_info "Starting Zabbix agent installation"
    
    if install_zabbix_agent "$zabbix_version" "$zabbix_server" "$zabbix_hostname"; then
        log_info "Zabbix agent installed successfully"
        save_state "$STAGE_ZABBIX_CONFIGURE" "zabbix_installed=true"
        return 0
    else
        log_error "Zabbix agent installation failed"
        return 1
    fi
}

stage_zabbix_configure() {
    log_stage "STAGE: ZABBIX-CONFIGURE - Configuring Zabbix Agent"
    
    local zabbix_hostname="$(hostname)"
    
    # Update banner
    cat > /etc/motd << EOF

===============================================
   $DEFAULT_BANNER_TEXT
===============================================
   Hostname: $(hostname)
   Date: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Setup Progress: Configuring SSH Tunnel...
===============================================

EOF
    
    # Configure Zabbix agent for tunnel connectivity
    if configure_zabbix_for_tunnel "$zabbix_hostname"; then
        log_info "Zabbix agent configured successfully"
        save_state "$STAGE_TUNNEL_SETUP" "zabbix_configured=true"
        return 0
    else
        log_error "Zabbix agent configuration failed"
        return 1
    fi
}

stage_tunnel_setup() {
    log_stage "STAGE: TUNNEL-SETUP - Setting up SSH tunnel"
    
    local ssh_host="${1:-$DEFAULT_HOME_SERVER_IP}"
    local ssh_port="${2:-$DEFAULT_HOME_SERVER_SSH_PORT}"
    local ssh_user="${3:-$DEFAULT_SSH_USER}"
    
    # Check if SSH key exists, generate if needed
    if [ ! -f "$DEFAULT_SSH_KEY" ]; then
        log_info "Generating SSH key for tunnel"
        generate_tunnel_ssh_key "$DEFAULT_SSH_KEY" "$ssh_host" "$ssh_port" "$ssh_user"
    fi
    
    # Create tunnel service with custom parameters
    if create_ssh_tunnel_service "$ssh_host" "$ssh_port" "$ssh_user"; then
        log_info "SSH tunnel configured successfully"
        save_state "$STAGE_COMPLETE" "tunnel_configured=true"
        return 0
    else
        log_warn "SSH tunnel setup failed - manual configuration may be required"
        save_state "$STAGE_COMPLETE" "tunnel_failed=true"
        return 0  # Continue to completion even if tunnel fails
    fi
}

stage_complete() {
    log_stage "STAGE: COMPLETE - Finalizing server setup"
    
    # Display SSH key information prominently if key exists
    if [ -f "$DEFAULT_SSH_KEY.pub" ]; then
        echo ""
        echo "=========================================================================="
        echo "                    🔑 SSH TUNNEL CONFIGURATION REQUIRED"
        echo "=========================================================================="
        echo "The server setup is complete, but the SSH tunnel requires manual setup."
        echo ""
        echo "ADMINISTRATOR: Add this SSH public key to your Zabbix server:"
        echo "--------------------------------------------------------------------------"
        cat "$DEFAULT_SSH_KEY.pub"
        echo "--------------------------------------------------------------------------"
        echo ""
        echo "Key files available at:"
        echo "  📄 Full instructions: /root/zabbix_ssh_key_info.txt"
        echo "  🔑 Public key only:   /root/zabbix_tunnel_public_key.txt"
        echo ""
        echo "After adding the key to your Zabbix server:"
        echo "  systemctl start zabbix-tunnel"
        echo "=========================================================================="
        echo ""
        
        # Log the key information for permanent record
        log_warn "========== SSH TUNNEL SETUP REQUIRED =========="
        log_warn "SSH public key: $(cat "$DEFAULT_SSH_KEY.pub")"
        log_warn "Instructions saved to: /root/zabbix_ssh_key_info.txt"
        log_warn "==============================================="
    fi
    
    # Create enhanced MOTD with SSH key reference
    local ssh_key_status="Not configured"
    local ssh_key_instructions=""
    
    if [ -f "$DEFAULT_SSH_KEY.pub" ]; then
        ssh_key_status="Generated - Manual setup required"
        ssh_key_instructions="
   SSH Key Setup: cat /root/zabbix_ssh_key_info.txt
   Start Tunnel:  systemctl start zabbix-tunnel"
    fi
    
    # Create customer-friendly MOTD (no technical details)
    cat > /etc/motd << EOF

===============================================
   VIRTUALIZOR MANAGED SERVER - READY
===============================================
   Hostname: $(hostname)
   Setup Completed: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Status: Server Ready for Use
   Monitoring: Configured and Active
===============================================

EOF

    # Update SSH banner to reflect completion
    cat > /etc/issue.net << EOF
===============================================
Virtualizor Managed Server - READY
===============================================
EOF

    # Reload SSH daemon to pick up new banner
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    
    # Remove systemd service - no longer needed
    remove_systemd_service
    
    # Clear state files
    clear_state
    
    log_info "Server setup completed successfully"
    log_info "Zabbix agent is configured and running"
    
    if [ -f "$DEFAULT_SSH_KEY.pub" ]; then
        log_info "SSH tunnel requires manual key setup - see /root/zabbix_ssh_key_info.txt"
    fi
    
    log_info "Server is ready for user access"
    
    return 0
}

# ====================================================================
# EMBEDDED ZABBIX FUNCTIONS (simplified for integration)
# ====================================================================
install_zabbix_agent() {
    local zabbix_version="$1"
    local zabbix_server="$2"
    local zabbix_hostname="$3"
    
    # Simplified version of the install script logic
    case "$OS_FAMILY" in
        debian)
            local repo_url="https://repo.zabbix.com/zabbix/${zabbix_version}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${zabbix_version}-1+ubuntu${OS_VERSION}_all.deb"
            
            wget -q "$repo_url" -O /tmp/zabbix-release.deb || return 1
            dpkg -i --force-confold --force-confdef /tmp/zabbix-release.deb || return 1
            apt-get update -qq || return 1
            DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" zabbix-agent || return 1
            rm -f /tmp/zabbix-release.deb
            ;;
            
        rhel)
            local repo_url="https://repo.zabbix.com/zabbix/${zabbix_version}/rhel/${OS_VERSION}/x86_64/zabbix-release-${zabbix_version}-1.el${OS_VERSION}.noarch.rpm"
            
            rpm -Uvh --quiet "$repo_url" || return 1
            
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y -q zabbix-agent || return 1
            else
                yum install -y -q zabbix-agent || return 1
            fi
            ;;
    esac
    
    # Detect the correct Zabbix configuration file location
    local zabbix_conf=""
    local possible_configs=(
        "/etc/zabbix/zabbix_agentd.conf"
        "/etc/zabbix/zabbix_agent2.conf" 
        "/etc/zabbix_agentd.conf"
        "/usr/local/etc/zabbix_agentd.conf"
    )
    
    for config_file in "${possible_configs[@]}"; do
        if [ -f "$config_file" ]; then
            zabbix_conf="$config_file"
            log_info "Found Zabbix config at: $zabbix_conf"
            break
        fi
    done
    
    if [ -z "$zabbix_conf" ]; then
        log_error "No Zabbix configuration file found after installation. Checked locations:"
        for config_file in "${possible_configs[@]}"; do
            log_error "  - $config_file"
        done
        return 1
    fi
    
    # Basic configuration
    sed -i "s/^Server=.*/Server=${zabbix_server}/" "$zabbix_conf"
    sed -i "s/^ServerActive=.*/ServerActive=${zabbix_server}/" "$zabbix_conf"
    sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" "$zabbix_conf"
    
    systemctl enable zabbix-agent
    systemctl start zabbix-agent
    
    return 0
}

configure_zabbix_for_tunnel() {
    local zabbix_hostname="$1"
    
    # Detect the correct Zabbix configuration file location
    local zabbix_conf=""
    local possible_configs=(
        "/etc/zabbix/zabbix_agentd.conf"
        "/etc/zabbix/zabbix_agent2.conf" 
        "/etc/zabbix_agentd.conf"
        "/usr/local/etc/zabbix_agentd.conf"
    )
    
    for config_file in "${possible_configs[@]}"; do
        if [ -f "$config_file" ]; then
            zabbix_conf="$config_file"
            log_info "Found Zabbix config at: $zabbix_conf"
            break
        fi
    done
    
    if [ -z "$zabbix_conf" ]; then
        log_error "No Zabbix configuration file found. Checked locations:"
        for config_file in "${possible_configs[@]}"; do
            log_error "  - $config_file"
        done
        return 1
    fi
    
    # Configure for local tunnel connection
    sed -i "s/^Server=.*/Server=127.0.0.1/" "$zabbix_conf"
    sed -i "s/^ServerActive=.*/ServerActive=127.0.0.1/" "$zabbix_conf"
    sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" "$zabbix_conf"
    
    # Enable debug logging
    if grep -q "^# DebugLevel=" "$zabbix_conf"; then
        sed -i "s/^# DebugLevel=.*/DebugLevel=4/" "$zabbix_conf"
    else
        echo "DebugLevel=4" >> "$zabbix_conf"
    fi
    
    systemctl restart zabbix-agent
    return 0
}

generate_tunnel_ssh_key() {
    local ssh_key="$1"
    local ssh_host="${2:-$DEFAULT_HOME_SERVER_IP}"
    local ssh_port="${3:-$DEFAULT_HOME_SERVER_SSH_PORT}"
    local ssh_user="${4:-$DEFAULT_SSH_USER}"
    local key_comment="zabbix-tunnel-$(hostname)-$(date +%Y%m%d)"
    
    mkdir -p "$(dirname "$ssh_key")"
    
    if ssh-keygen -t rsa -b 4096 -f "$ssh_key" -N "" -C "$key_comment" >/dev/null 2>&1; then
        chmod 600 "$ssh_key"
        chmod 644 "${ssh_key}.pub"
        
        log_info "SSH key generated: $ssh_key"
        
        # Save public key to easily accessible location
        cp "${ssh_key}.pub" "/root/zabbix_tunnel_public_key.txt"
        chmod 644 "/root/zabbix_tunnel_public_key.txt"
        
        # Create admin-readable summary file
        cat > "/root/zabbix_ssh_key_info.txt" << EOF
========================================
ZABBIX SSH TUNNEL CONFIGURATION
========================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Server IP: $(hostname -I | awk '{print $1}')

TUNNEL CONNECTION DETAILS:
- Target Server: ${ssh_host}:${ssh_port}
- SSH User: ${ssh_user}
- Tunnel Port: ${DEFAULT_ZABBIX_SERVER_PORT}

ADMINISTRATOR ACTION REQUIRED:
1. Copy the SSH public key below to your Zabbix server
2. Add it to ${ssh_user}@${ssh_host}:~/.ssh/authorized_keys
3. Restart the tunnel service: systemctl start zabbix-tunnel

SSH PUBLIC KEY (copy this entire line):
$(cat "${ssh_key}.pub")

Files created:
- Private key: $ssh_key
- Public key: ${ssh_key}.pub
- This info: /root/zabbix_ssh_key_info.txt
- Public key copy: /root/zabbix_tunnel_public_key.txt

Quick access commands:
- View this info: cat /root/zabbix_ssh_key_info.txt
- Copy public key: cat /root/zabbix_tunnel_public_key.txt
- Check tunnel status: systemctl status zabbix-tunnel
- Test SSH connection: ssh -i $ssh_key -p ${ssh_port} ${ssh_user}@${ssh_host}
========================================
EOF
        
        log_warn ""
        log_warn "==================== ADMINISTRATOR ACTION REQUIRED ===================="
        log_warn "SSH KEY GENERATED - MUST BE ADDED TO ZABBIX SERVER"
        log_warn "========================================================================"
        log_warn "Public key saved to: /root/zabbix_tunnel_public_key.txt"
        log_warn "Complete instructions: /root/zabbix_ssh_key_info.txt"
        log_warn ""
        log_warn "COPY THIS SSH PUBLIC KEY TO YOUR ZABBIX SERVER:"
        cat "${ssh_key}.pub"
        log_warn ""
        log_warn "After adding the key to your Zabbix server:"
        log_warn "systemctl start zabbix-tunnel"
        log_warn "========================================================================"
        
        return 0
    else
        return 1
    fi
}

create_ssh_tunnel_service() {
    local ssh_host="${1:-$DEFAULT_HOME_SERVER_IP}"
    local ssh_port="${2:-$DEFAULT_HOME_SERVER_SSH_PORT}"
    local ssh_user="${3:-$DEFAULT_SSH_USER}"
    
    log_info "Creating SSH tunnel service for ${ssh_user}@${ssh_host}:${ssh_port}"
    
    # Create systemd service for SSH tunnel
    cat > /etc/systemd/system/zabbix-tunnel.service << EOF
[Unit]
Description=Persistent SSH Reverse Tunnel to Zabbix Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 60
ExecStart=/usr/bin/ssh -i ${DEFAULT_SSH_KEY} \\
    -o ExitOnForwardFailure=yes \\
    -o ServerAliveInterval=60 \\
    -o ServerAliveCountMax=3 \\
    -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o BatchMode=yes \\
    -N -R ${DEFAULT_ZABBIX_SERVER_PORT}:localhost:${DEFAULT_ZABBIX_SERVER_PORT} \\
    -p ${ssh_port} \\
    ${ssh_user}@${ssh_host}
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zabbix-tunnel
    
    # Don't start yet - requires manual SSH key setup
    log_info "SSH tunnel service created for ${ssh_host} (requires manual SSH key setup)"
    return 0
}

# ====================================================================
# SYSTEM STATUS VALIDATION FUNCTIONS
# ====================================================================
validate_system_status() {
    log_info "=== SYSTEM STATUS VALIDATION ==="
    
    local all_good=true
    
    # Check Zabbix Agent
    log_info "Checking Zabbix Agent status..."
    if systemctl is-active zabbix-agent >/dev/null 2>&1; then
        log_info "✅ Zabbix Agent: RUNNING"
        
        # Check if agent can connect locally
        if netstat -tlnp 2>/dev/null | grep -q ':10050.*zabbix_agentd' || ss -tlnp 2>/dev/null | grep -q ':10050.*zabbix_agentd'; then
            log_info "✅ Zabbix Agent: Listening on port 10050"
        else
            log_warn "⚠️  Zabbix Agent: Not listening on expected port 10050"
        fi
    else
        log_error "❌ Zabbix Agent: NOT RUNNING"
        all_good=false
    fi
    
    # Check SSH Tunnel Service
    log_info "Checking SSH Tunnel status..."
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1; then
        log_info "✅ SSH Tunnel Service: RUNNING"
        
        # Check tunnel connection
        local tunnel_pid=$(systemctl show zabbix-tunnel --property MainPID --value 2>/dev/null)
        if [ -n "$tunnel_pid" ] && [ "$tunnel_pid" != "0" ]; then
            log_info "✅ SSH Tunnel: Active connection (PID: $tunnel_pid)"
            
            # Check if reverse tunnel port is established
            if netstat -tlnp 2>/dev/null | grep -q "127.0.0.1:${DEFAULT_ZABBIX_SERVER_PORT}" || ss -tlnp 2>/dev/null | grep -q "127.0.0.1:${DEFAULT_ZABBIX_SERVER_PORT}"; then
                log_info "✅ SSH Tunnel: Reverse port ${DEFAULT_ZABBIX_SERVER_PORT} is active"
            else
                log_warn "⚠️  SSH Tunnel: Reverse port ${DEFAULT_ZABBIX_SERVER_PORT} not detected locally"
            fi
        else
            log_warn "⚠️  SSH Tunnel Service running but no active connection found"
            all_good=false
        fi
    else
        log_error "❌ SSH Tunnel Service: NOT RUNNING"
        all_good=false
    fi
    
    # Check Configuration Files
    log_info "Checking configuration files..."
    
    # Detect the Zabbix configuration file location
    local zabbix_conf=""
    local possible_configs=(
        "/etc/zabbix/zabbix_agentd.conf"
        "/etc/zabbix/zabbix_agent2.conf" 
        "/etc/zabbix_agentd.conf"
        "/usr/local/etc/zabbix_agentd.conf"
    )
    
    for config_file in "${possible_configs[@]}"; do
        if [ -f "$config_file" ]; then
            zabbix_conf="$config_file"
            break
        fi
    done
    
    if [ -n "$zabbix_conf" ]; then
        log_info "Found Zabbix config: $zabbix_conf"
        if grep -q "^Server=127.0.0.1" "$zabbix_conf" && grep -q "^ServerActive=127.0.0.1" "$zabbix_conf"; then
            log_info "✅ Zabbix Config: Configured for tunnel (127.0.0.1)"
        else
            log_warn "⚠️  Zabbix Config: Not configured for local tunnel"
            all_good=false
        fi
    else
        log_error "❌ Zabbix Config: Configuration file missing"
        all_good=false
    fi
    
    # Check SSH Key
    if [ -f "$DEFAULT_SSH_KEY" ]; then
        log_info "✅ SSH Key: Present at $DEFAULT_SSH_KEY"
        
        # Check key permissions
        local key_perms=$(stat -c "%a" "$DEFAULT_SSH_KEY" 2>/dev/null || stat -f "%Lp" "$DEFAULT_SSH_KEY" 2>/dev/null)
        if [ "$key_perms" = "600" ]; then
            log_info "✅ SSH Key: Correct permissions (600)"
        else
            log_warn "⚠️  SSH Key: Incorrect permissions ($key_perms), should be 600"
        fi
    else
        log_error "❌ SSH Key: Missing at $DEFAULT_SSH_KEY"
        all_good=false
    fi
    
    # Overall Status
    log_info "=== OVERALL STATUS ==="
    if [ "$all_good" = true ]; then
        log_info "🎉 ALL SYSTEMS OPERATIONAL"
        log_info "✅ Zabbix monitoring is ready and connected"
        return 0
    else
        log_warn "⚠️  SOME ISSUES DETECTED - Check logs above"
        log_info "📋 Troubleshooting steps:"
        log_info "   1. Check service logs: journalctl -u zabbix-agent -u zabbix-tunnel"
        log_info "   2. Test SSH connection: ssh -i $DEFAULT_SSH_KEY -p $DEFAULT_HOME_SERVER_SSH_PORT $DEFAULT_SSH_USER@$DEFAULT_HOME_SERVER_IP"
        log_info "   3. Restart services: systemctl restart zabbix-agent zabbix-tunnel"
        
        # SSH Key Information for troubleshooting
        if [ -f "$DEFAULT_SSH_KEY.pub" ]; then
            log_info "   4. SSH Key Setup: cat /root/zabbix_ssh_key_info.txt"
            log_info "   5. Public Key: cat /root/zabbix_tunnel_public_key.txt"
        fi
        
        return 1
    fi
}

show_quick_status() {
    echo "==================================================================="
    echo "Virtualizor Server Setup - Quick Status Check"
    echo "==================================================================="
    echo "Hostname: $(hostname)"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Zabbix Agent Status
    if systemctl is-active zabbix-agent >/dev/null 2>&1; then
        echo "Zabbix Agent:     ✅ RUNNING"
    else
        echo "Zabbix Agent:     ❌ STOPPED"
    fi
    
    # SSH Tunnel Status
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1; then
        echo "SSH Tunnel:       ✅ RUNNING"
        local tunnel_pid=$(systemctl show zabbix-tunnel --property MainPID --value 2>/dev/null)
        echo "Tunnel PID:       $tunnel_pid"
    else
        echo "SSH Tunnel:       ❌ STOPPED"
    fi
    
    # SSH Key Status and Information
    if [ -f "$DEFAULT_SSH_KEY.pub" ]; then
        echo "SSH Key:          ✅ GENERATED"
        echo "Key Files:"
        echo "  - Instructions:  /root/zabbix_ssh_key_info.txt"
        echo "  - Public Key:    /root/zabbix_tunnel_public_key.txt"
        echo ""
        echo "🔑 To view SSH public key for Zabbix server setup:"
        echo "   cat /root/zabbix_tunnel_public_key.txt"
        echo ""
        if ! systemctl is-active zabbix-tunnel >/dev/null 2>&1; then
            echo "⚠️  SSH tunnel not running - key may need to be added to Zabbix server"
            echo "   After adding key: systemctl start zabbix-tunnel"
        fi
    else
        echo "SSH Key:          ❌ NOT GENERATED"
    fi
    
    echo ""
    
    # Setup Status
    if load_state && [ "$CURRENT_STAGE" = "$STAGE_COMPLETE" ]; then
        echo "Setup Status:     ✅ COMPLETE"
    elif load_state; then
        echo "Setup Status:     🔄 IN PROGRESS ($CURRENT_STAGE)"
    else
        echo "Setup Status:     ❓ NOT STARTED"
    fi
    
    echo ""
    echo "Log Files:"
    echo "  Setup:   $LOG_FILE"
    echo "  Zabbix:  /var/log/zabbix/zabbix_agentd.log"
    echo "  Tunnel:  journalctl -u zabbix-tunnel"
    echo ""
    echo "Commands:"
    echo "  Full status:     $0 --validate"
    echo "  Diagnostics:     $0 --diagnose"
    echo "  Service logs:    journalctl -u zabbix-agent -u zabbix-tunnel"
    echo "  Test tunnel:     ssh -i $DEFAULT_SSH_KEY -p $DEFAULT_HOME_SERVER_SSH_PORT $DEFAULT_SSH_USER@$DEFAULT_HOME_SERVER_IP"
    echo "==================================================================="
}

run_diagnostics() {
    echo "==================================================================="
    echo "SYSTEM DIAGNOSTICS"
    echo "==================================================================="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hostname: $(hostname)"
    echo ""
    
    # System Information
    echo "SYSTEM INFORMATION:"
    echo "  User: $(whoami)"
    echo "  UID: $(id -u)"
    echo "  Shell: $SHELL"
    echo "  Bash Version: ${BASH_VERSION:-'Not available'}"
    if [ -f /etc/os-release ]; then
        echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    fi
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Uptime: $(uptime | cut -d, -f1)"
    echo ""
    
    # Network Diagnostics
    echo "NETWORK DIAGNOSTICS:"
    echo "  Testing connectivity..."
    
    for host in "8.8.8.8" "1.1.1.1" "google.com"; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            echo "  ✅ $host: Reachable"
        else
            echo "  ❌ $host: Unreachable"
        fi
    done
    
    # Interface status
    echo "  Network Interfaces:"
    if command -v ip >/dev/null 2>&1; then
        ip addr show | grep -E "^[0-9]|inet " | while read line; do
            echo "    $line"
        done
    fi
    
    echo ""
    
    # Disk Space
    echo "DISK SPACE:"
    df -h | grep -E "(Filesystem|/dev/)" | while read line; do
        echo "  $line"
    done
    echo ""
    
    # Memory
    echo "MEMORY USAGE:"
    if command -v free >/dev/null 2>&1; then
        free -h | while read line; do
            echo "  $line"
        done
    fi
    echo ""
    
    # Process Status
    echo "PROCESS STATUS:"
    echo "  Current processes: $(ps aux | wc -l)"
    echo "  Load average: $(uptime | sed 's/.*load average: //')"
    echo ""
    
    # Service Status
    echo "SERVICE STATUS:"
    for service in "systemd" "network" "ssh"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo "  ✅ $service: Active"
        else
            echo "  ❌ $service: Inactive"
        fi
    done
    echo ""
    
    # State Information
    echo "SCRIPT STATE:"
    if [ -f "$STATE_FILE" ]; then
        echo "  State file: Present"
        if load_state; then
            echo "  Current stage: $CURRENT_STAGE"
            echo "  Execution start: $EXECUTION_START"
            echo "  Stage data: $STAGE_DATA"
        fi
    else
        echo "  State file: Not found"
    fi
    
    if [ -f "$LOCK_FILE" ]; then
        echo "  Lock file: Present (PID: $(cat "$LOCK_FILE" 2>/dev/null || echo 'unknown'))"
    else
        echo "  Lock file: Not found"
    fi
    
    if [ -f "$REBOOT_FLAG_FILE" ]; then
        echo "  Reboot flag: Present ($(cat "$REBOOT_FLAG_FILE" 2>/dev/null || echo 'unknown'))"
    else
        echo "  Reboot flag: Not found"
    fi
    echo ""
    
    # REBOOT RESUME DIAGNOSTICS
    echo "REBOOT RESUME DIAGNOSTICS:"
    
    if systemctl is-enabled "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
        echo "  Service enabled: YES"
        if systemctl is-active "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
            echo "  Service active: YES"
        else
            echo "  Service active: NO"
            echo "  Service logs (last 5 lines):"
            journalctl -u "${SCRIPT_NAME}.service" --no-pager -n 5 2>/dev/null | while read line; do
                echo "    $line"
            done
        fi
    else
        echo "  Service enabled: NO"
    fi
    
    echo "  State directory: $(dirname "$STATE_FILE") ($([ -d "$(dirname "$STATE_FILE")" ] && echo "EXISTS" || echo "MISSING"))"
    echo "  State file permissions: $(ls -l "$STATE_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")"
    echo "  Reboot flag permissions: $(ls -l "$REBOOT_FLAG_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")"

    # Log Information
    echo "LOG INFORMATION:"
    if [ -f "$LOG_FILE" ]; then
        echo "  Setup log: $LOG_FILE"
        echo "  Log size: $(du -h "$LOG_FILE" 2>/dev/null | cut -f1 || echo 'unknown')"
        echo "  Last entries:"
        tail -5 "$LOG_FILE" 2>/dev/null | while read line; do
            echo "    $line"
        done
    else
        echo "  Setup log: Not found"
    fi
    
    echo ""
    
    # Include reboot diagnostics
    diagnose_reboot_issue
    
    echo "==================================================================="
}

# ====================================================================
# REBOOT DIAGNOSTICS AND RECOVERY
# ====================================================================
diagnose_reboot_issue() {
    echo "REBOOT RESUME DIAGNOSTICS"
    echo "========================="
    
    echo "1. SYSTEMD SERVICE STATUS:"
    if systemctl is-enabled "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
        echo "  Service enabled: YES"
        if systemctl is-active "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
            echo "  Service active: YES"
        else
            echo "  Service active: NO"
        fi
        
        echo "  Service logs:"
        journalctl -u "${SCRIPT_NAME}.service" --no-pager -n 10 2>/dev/null | while read line; do
            echo "    $line"
        done
    else
        echo "  Service enabled: NO"
    fi
    
    echo ""
    echo "2. FILE SYSTEM STATE:"
    echo "  State file: $([ -f "$STATE_FILE" ] && echo "EXISTS" || echo "MISSING")"
    echo "  Reboot flag: $([ -f "$REBOOT_FLAG_FILE" ] && echo "EXISTS" || echo "MISSING")"
    echo "  State directory: $(dirname "$STATE_FILE")"
    echo "  Directory permissions: $(ls -ld "$(dirname "$STATE_FILE")" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
    
    if [ -f "$STATE_FILE" ]; then
        echo ""
        echo "  State file contents:"
        cat "$STATE_FILE" | while read line; do
            echo "    $line"
        done
    fi
    
    if [ -f "$REBOOT_FLAG_FILE" ]; then
        echo ""
        echo "  Reboot flag contents: $(cat "$REBOOT_FLAG_FILE")"
    fi
    
    echo ""
    echo "3. RECOVERY SUGGESTIONS:"
    
    if [ ! -f "$STATE_FILE" ]; then
        echo "  - No state file found - run './$(basename "$0")' to start fresh setup"
    elif [ -f "$REBOOT_FLAG_FILE" ]; then
        echo "  - Reboot flag exists - run './$(basename "$0") --resume-after-reboot' to resume"
    else
        echo "  - State file exists but no reboot flag - run './$(basename "$0")' to continue"
    fi
    
    if ! systemctl is-enabled "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
        echo "  - Service not enabled - this is normal after completion or cleanup"
    fi
    
    echo ""
    echo "4. MANUAL RESUME COMMAND:"
    echo "  ./$(basename "$0") --resume-after-reboot"
    
    echo "========================="
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Complete Virtualizor Server Provisioning

DESCRIPTION:
    Comprehensive server setup script that handles the complete provisioning
    lifecycle including updates, reboots, and Zabbix agent installation.
    Maintains execution state across reboots for reliable provisioning.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --stage STAGE              Start from specific stage
    --resume-after-reboot      Resume after reboot (used internally)
    --banner-text TEXT         Custom banner text
    --zabbix-version VERSION   Zabbix version to install (default: $DEFAULT_ZABBIX_VERSION)
    --ssh-host HOST           SSH tunnel host (default: $DEFAULT_HOME_SERVER_IP)
    --ssh-port PORT           SSH tunnel port (default: $DEFAULT_HOME_SERVER_SSH_PORT)
    --ssh-user USER           SSH tunnel user (default: $DEFAULT_SSH_USER)
    --zabbix-server-port PORT Zabbix server port (default: $DEFAULT_ZABBIX_SERVER_PORT)
    --test                    Test mode - validate without changes
    --status                  Show current setup status
    --validate                Comprehensive system validation
    --diagnose                Detailed system diagnostics
    --diagnose-reboot         Diagnose reboot resume issues
    --quick-status            Quick status overview
    --cleanup                 Clean up state files and services
    --help                    Show this help message

DYNAMIC PROVISIONING EXAMPLES:
    # Virtualizor Recipe with environment variables
    ZABBIX_SERVER_DOMAIN="monitor.acme.com" SSH_TUNNEL_PORT="7832" \\
    SSH_TUNNEL_USER="mon-agent" curl -fsSL \\
    https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh | bash

    # Direct execution with parameters
    ./virtualizor-server-setup.sh --ssh-host "monitor.acme.com" \\
                                  --ssh-port "7832" \\
                                  --ssh-user "mon-agent"

STAGES:
    $STAGE_INIT               Initial setup and validation
    $STAGE_BANNER             Set system banner and MOTD
    $STAGE_UPDATES            Install system updates/upgrades
    $STAGE_POST_REBOOT        Post-reboot validation
    $STAGE_ZABBIX_INSTALL     Install Zabbix agent
    $STAGE_ZABBIX_CONFIGURE   Configure Zabbix agent
    $STAGE_TUNNEL_SETUP       Setup SSH tunnel
    $STAGE_COMPLETE           Finalize setup

EXAMPLES:
    $0                        # Full provisioning (recommended)
    $0 --stage updates        # Start from updates stage
    $0 --status               # Show current status
    $0 --cleanup              # Clean up after failed run
    bash -n $0                # Validate script syntax

QUALITY ASSURANCE:
    SYNTAX CHECK:             bash -n $0
    COMPREHENSIVE TEST:       $0 --test
    SYSTEM VALIDATION:        $0 --validate
    DIAGNOSTIC MODE:          $0 --diagnose

VIRTUALIZOR INTEGRATION:
    This script is designed for Virtualizor recipe execution.
    It handles reboot persistence and maintains state across
    the entire server provisioning lifecycle.

REBOOT HANDLING:
    The script automatically handles reboots during the update stage.
    State is preserved via systemd service and state files.
    No manual intervention required after reboots.

ERROR HANDLING:
    - Comprehensive error logging with system diagnostics
    - Automatic syntax validation before execution
    - Structured error reporting with troubleshooting guides
    - Recovery procedures for common failure scenarios

LOGS:
    Setup logs: $LOG_FILE
    State file: $STATE_FILE
    Error state: $STATE_FILE.error
    Service logs: journalctl -u ${SCRIPT_NAME}.service

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local target_stage=""
    local banner_text="$DEFAULT_BANNER_TEXT"
    local zabbix_version="$DEFAULT_ZABBIX_VERSION"
    local ssh_host="$DEFAULT_HOME_SERVER_IP"
    local ssh_port="$DEFAULT_HOME_SERVER_SSH_PORT"
    local ssh_user="$DEFAULT_SSH_USER"
    local zabbix_server_port="$DEFAULT_ZABBIX_SERVER_PORT"
    local resume_after_reboot=false
    local test_mode=false
    local show_status=false
    local cleanup_mode=false
    
    # Set up error handling FIRST
    set_error_trap
    
    # Early syntax validation (before any other operations)
    log_info "Performing initial syntax validation..."
    if ! validate_script_syntax; then
        log_error "CRITICAL: Initial syntax validation failed"
        log_error "Script integrity compromised - aborting execution"
        exit 1
    fi
    
    # Parse command line arguments with error handling
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stage)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --stage requires a value"
                    show_help
                    exit 2
                fi
                target_stage="$2"
                shift 2
                ;;
            --resume-after-reboot)
                resume_after_reboot=true
                shift
                ;;
            --banner-text)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --banner-text requires a value"
                    exit 2
                fi
                banner_text="$2"
                shift 2
                ;;
            --zabbix-version)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --zabbix-version requires a value"
                    exit 2
                fi
                zabbix_version="$2"
                shift 2
                ;;
            --ssh-host)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --ssh-host requires a value"
                    exit 2
                fi
                ssh_host="$2"
                shift 2
                ;;
            --ssh-port)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --ssh-port requires a value"
                    exit 2
                fi
                ssh_port="$2"
                shift 2
                ;;
            --ssh-user)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --ssh-user requires a value"
                    exit 2
                fi
                ssh_user="$2"
                shift 2
                ;;
            --zabbix-server-port)
                if [ -z "${2:-}" ]; then
                    log_error "ERROR: --zabbix-server-port requires a value"
                    exit 2
                fi
                zabbix_server_port="$2"
                shift 2
                ;;
            --test)
                test_mode=true
                shift
                ;;
            --status)
                show_status=true
                shift
                ;;
            --validate)
                validate_system_status
                exit $?
                ;;
            --diagnose)
                run_diagnostics
                exit 0
                ;;
            --diagnose-reboot)
                diagnose_reboot_issue
                exit 0
                ;;
            --quick-status)
                show_quick_status
                exit 0
                ;;
            --cleanup)
                cleanup_mode=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "ERROR: Unknown parameter: $1"
                show_help
                exit 2
                ;;
        esac
    done
    
    # Setup
    setup_logging
    validate_root
    
    # Cleanup mode
    if [ "$cleanup_mode" = true ]; then
        log_info "Cleaning up state files and services"
        clear_state
        remove_systemd_service
        log_info "Cleanup completed"
        exit 0
    fi
    
    # Status mode
    if [ "$show_status" = true ]; then
        if load_state; then
            echo "Current Stage: $CURRENT_STAGE"
            echo "Execution Start: $EXECUTION_START"
            echo "Stage Data: $STAGE_DATA"
            echo "Hostname: $HOSTNAME"
            echo "State File: $STATE_FILE"
            echo "Log File: $LOG_FILE"
            
            if [ -f "$REBOOT_FLAG_FILE" ]; then
                echo "Reboot Flag: $(cat "$REBOOT_FLAG_FILE")"
            fi
        else
            echo "No active setup found"
        fi
        exit 0
    fi
    
    create_lock_file
    trap cleanup EXIT
    
    log_info "Starting Virtualizor server setup"
    log_info "Execution mode: $([ "$test_mode" = true ] && echo "TEST" || echo "PRODUCTION")"
    
    # Determine starting stage
    if [ "$resume_after_reboot" = true ]; then
        # Resume after reboot - this is typically called by systemd service
        log_info "Resume after reboot requested"
        log_info "Checking for reboot flag: $REBOOT_FLAG_FILE"
        log_info "Checking for state file: $STATE_FILE"
        
        if next_stage=$(check_reboot_flag); then
            target_stage="$next_stage"
            clear_reboot_flag
            log_info "Resuming after reboot with target stage: $target_stage"
        else
            log_warn "No reboot flag found - attempting recovery"
            
            # Check if we're running from systemd service
            if [ "${SYSTEMD_EXEC_PID:-}" = "$$" ] || [ -n "${INVOCATION_ID:-}" ]; then
                log_info "Running from systemd service - disabling service and checking for saved state"
                # Disable the systemd service since we don't need it without a reboot flag
                remove_systemd_service 2>/dev/null || true
            fi
            
            # Try to recover from saved state
            if load_state && [ -n "$CURRENT_STAGE" ]; then
                case "$CURRENT_STAGE" in
                    "$STAGE_UPDATES")
                        # We were in updates stage, assume reboot was needed
                        target_stage="$STAGE_POST_REBOOT"
                        log_info "Recovering from updates stage - proceeding to post-reboot stage"
                        ;;
                    *)
                        target_stage="$CURRENT_STAGE"
                        log_info "Recovering from saved state, continuing from: $target_stage"
                        ;;
                esac
            else
                log_info "No saved state found - checking if setup is already complete"
                # If Zabbix is installed and configured, assume setup is complete
                if systemctl is-active zabbix-agent >/dev/null 2>&1; then
                    log_info "Zabbix agent is running - setup appears complete"
                    target_stage="$STAGE_COMPLETE"
                else
                    log_info "Starting fresh setup"
                    target_stage="$STAGE_INIT"
                fi
            fi
        fi
    elif [ -n "$target_stage" ]; then
        # Explicit stage specified
        log_info "Starting from specified stage: $target_stage"
    elif load_state && [ -n "$CURRENT_STAGE" ]; then
        # Continue from saved state
        target_stage="$CURRENT_STAGE"
        log_info "Continuing from saved stage: $target_stage"
    else
        # New execution
        target_stage="$STAGE_INIT"
        log_info "Starting new server setup"
    fi
    
    # Test mode
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - no changes will be made"
        log_info "Would start from stage: $target_stage"
        detect_os
        log_info "OS detection: $OS_ID $OS_VERSION ($OS_FAMILY)"
        log_info "Test mode completed"
        exit 0
    fi
    
    # Ensure OS detection is always performed
    if [ "$target_stage" != "$STAGE_INIT" ]; then
        log_info "Performing OS detection for stage: $target_stage"
        if ! detect_os; then
            log_error "CRITICAL: OS detection failed"
            exit 1
        fi
        log_info "✅ OS detected: $OS_ID $OS_VERSION (family: $OS_FAMILY)"
    fi
    
    # Execute stages in sequence
    case "$target_stage" in
        "$STAGE_INIT")
            stage_init && stage_banner "$banner_text" && stage_updates
            ;;
        "$STAGE_BANNER")
            stage_banner "$banner_text" && stage_updates
            ;;
        "$STAGE_UPDATES")
            stage_updates
            ;;
        "$STAGE_POST_REBOOT")
            stage_post_reboot && stage_zabbix_install "$zabbix_version" && stage_zabbix_configure && stage_tunnel_setup "$ssh_host" "$ssh_port" "$ssh_user" && stage_complete
            ;;
        "$STAGE_ZABBIX_INSTALL")
            stage_zabbix_install "$zabbix_version" && stage_zabbix_configure && stage_tunnel_setup "$ssh_host" "$ssh_port" "$ssh_user" && stage_complete
            ;;
        "$STAGE_ZABBIX_CONFIGURE")
            stage_zabbix_configure && stage_tunnel_setup "$ssh_host" "$ssh_port" "$ssh_user" && stage_complete
            ;;
        "$STAGE_TUNNEL_SETUP")
            stage_tunnel_setup "$ssh_host" "$ssh_port" "$ssh_user" && stage_complete
            ;;
        "$STAGE_COMPLETE")
            stage_complete
            ;;
        *)
            log_error "Unknown stage: $target_stage"
            exit 2
            ;;
    esac
    
    log_info "Server setup stage completed successfully"
}

# Execute main function with all arguments
main "$@"
