#!/bin/bash
# ====================================================================
# Script: virtualizor-server-setup.sh - Complete Virtualizor Server Provisioning
# Usage: ./virtualizor-server-setup.sh [--stage STAGE] [--config-file PATH] [--test]
# Virtualizor-ready: Designed for automated server provisioning with reboot persistence
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
readonly STATE_FILE="/var/run/${SCRIPT_NAME}.state"
readonly REBOOT_FLAG_FILE="/var/run/${SCRIPT_NAME}.reboot"
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

# Zabbix configuration
readonly DEFAULT_ZABBIX_VERSION="6.4"
readonly DEFAULT_ZABBIX_SERVER="127.0.0.1"
readonly DEFAULT_HOME_SERVER_IP="monitor.cloudgeeks.in"
readonly DEFAULT_HOME_SERVER_SSH_PORT=20202
readonly DEFAULT_ZABBIX_SERVER_PORT=10051
readonly DEFAULT_SSH_USER="zabbixssh"
readonly DEFAULT_SSH_KEY="/root/.ssh/zabbix_tunnel_key"
readonly DEFAULT_ADMIN_USER="root"
readonly DEFAULT_ADMIN_KEY="/root/.ssh/id_rsa"

# System settings
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30
readonly REBOOT_TIMEOUT=300  # 5 minutes wait after reboot
readonly UPDATE_TIMEOUT=1800  # 30 minutes for updates

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
    
    cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Virtualizor Server Setup - Reboot Persistent
After=network.target network-online.target
Wants=network-online.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=$0 --resume-after-reboot
RemainAfterExit=no
StandardOutput=journal
StandardError=journal
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF

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
    
    # Don't remove state file on normal exit - needed for reboot persistence
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
        # Keep state file for troubleshooting
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
    
    log_info "Waiting for network connectivity"
    
    while [ $count -lt $timeout ]; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_info "Network connectivity confirmed"
            return 0
        fi
        
        count=$((count + 5))
        sleep 5
        
        if [ $((count % 30)) -eq 0 ]; then
            log_info "Still waiting for network... (${count}s elapsed)"
        fi
    done
    
    log_error "Network connectivity timeout after ${timeout}s"
    return 3
}

# ====================================================================
# STAGE IMPLEMENTATION FUNCTIONS
# ====================================================================
stage_init() {
    log_stage "STAGE: INIT - Initial setup and validation"
    
    detect_os
    wait_for_network
    create_systemd_service
    
    save_state "$STAGE_BANNER" "os_detected=$OS_ID-$OS_VERSION"
    log_info "Initialization completed, proceeding to banner setup"
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
            log_info "Updating package lists"
            if ! timeout $UPDATE_TIMEOUT apt-get update -qq; then
                log_error "Package list update failed or timed out"
                return 1
            fi
            
            log_info "Checking for available upgrades"
            local upgrades=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
            if [ "$upgrades" -gt 0 ]; then
                log_info "Found $upgrades packages to upgrade"
                update_required=true
                
                log_info "Installing system updates"
                if ! timeout $UPDATE_TIMEOUT env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
                    log_error "System upgrade failed or timed out"
                    return 1
                fi
                
                log_info "Installing security updates"
                if ! timeout $UPDATE_TIMEOUT env DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y; then
                    log_warn "Security upgrade failed or timed out, continuing"
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
            
            local updates=$($package_manager check-update -q | wc -l || echo "0")
            if [ "$updates" -gt 0 ]; then
                log_info "Found updates available"
                update_required=true
                
                log_info "Installing system updates"
                if ! timeout $UPDATE_TIMEOUT $package_manager update -y -q; then
                    log_error "System update failed or timed out"
                    return 1
                fi
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
    
    # Check if SSH key exists, generate if needed
    if [ ! -f "$DEFAULT_SSH_KEY" ]; then
        log_info "Generating SSH key for tunnel"
        generate_tunnel_ssh_key "$DEFAULT_SSH_KEY"
    fi
    
    # Create tunnel service
    if create_ssh_tunnel_service; then
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
    
    # Final banner update
    cat > /etc/motd << EOF

===============================================
   VIRTUALIZOR MANAGED SERVER - READY
===============================================
   Hostname: $(hostname)
   Setup Completed: $(date '+%Y-%m-%d %H:%M:%S')
   
   $DEFAULT_MOTD_MESSAGE
   
   Status: Server Ready for Use
   Zabbix Agent: Configured and Running
   SSH Tunnel: Check logs for status
===============================================

EOF
    
    # Remove systemd service - no longer needed
    remove_systemd_service
    
    # Clear state files
    clear_state
    
    log_info "Server setup completed successfully"
    log_info "Zabbix agent is configured and running"
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
            dpkg -i /tmp/zabbix-release.deb || return 1
            apt-get update -qq || return 1
            DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-agent || return 1
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
    
    # Basic configuration
    sed -i "s/^Server=.*/Server=${zabbix_server}/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^ServerActive=.*/ServerActive=${zabbix_server}/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" /etc/zabbix/zabbix_agentd.conf
    
    systemctl enable zabbix-agent
    systemctl start zabbix-agent
    
    return 0
}

configure_zabbix_for_tunnel() {
    local zabbix_hostname="$1"
    
    # Configure for local tunnel connection
    sed -i "s/^Server=.*/Server=127.0.0.1/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^ServerActive=.*/ServerActive=127.0.0.1/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" /etc/zabbix/zabbix_agentd.conf
    
    # Enable debug logging
    if grep -q "^# DebugLevel=" /etc/zabbix/zabbix_agentd.conf; then
        sed -i "s/^# DebugLevel=.*/DebugLevel=4/" /etc/zabbix/zabbix_agentd.conf
    else
        echo "DebugLevel=4" >> /etc/zabbix/zabbix_agentd.conf
    fi
    
    systemctl restart zabbix-agent
    return 0
}

generate_tunnel_ssh_key() {
    local ssh_key="$1"
    local key_comment="zabbix-tunnel-$(hostname)-$(date +%Y%m%d)"
    
    mkdir -p "$(dirname "$ssh_key")"
    
    if ssh-keygen -t rsa -b 4096 -f "$ssh_key" -N "" -C "$key_comment" >/dev/null 2>&1; then
        chmod 600 "$ssh_key"
        chmod 644 "${ssh_key}.pub"
        
        log_info "SSH key generated: $ssh_key"
        log_warn "MANUAL ACTION REQUIRED:"
        log_warn "Copy the following public key to the remote server:"
        cat "${ssh_key}.pub"
        return 0
    else
        return 1
    fi
}

create_ssh_tunnel_service() {
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
    -p ${DEFAULT_HOME_SERVER_SSH_PORT} \\
    ${DEFAULT_SSH_USER}@${DEFAULT_HOME_SERVER_IP}
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
    log_info "SSH tunnel service created (requires manual SSH key setup)"
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
    if [ -f "$ZBX_CONF" ]; then
        if grep -q "^Server=127.0.0.1" "$ZBX_CONF" && grep -q "^ServerActive=127.0.0.1" "$ZBX_CONF"; then
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
    echo "  Service logs:    journalctl -u zabbix-agent -u zabbix-tunnel"
    echo "  Test tunnel:     ssh -i $DEFAULT_SSH_KEY -p $DEFAULT_HOME_SERVER_SSH_PORT $DEFAULT_SSH_USER@$DEFAULT_HOME_SERVER_IP"
    echo "==================================================================="
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
    --test                    Test mode - validate without changes
    --status                  Show current setup status
    --validate                Comprehensive system validation
    --quick-status            Quick status overview
    --cleanup                 Clean up state files and services
    --help                    Show this help message

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

VIRTUALIZOR INTEGRATION:
    This script is designed for Virtualizor recipe execution.
    It handles reboot persistence and maintains state across
    the entire server provisioning lifecycle.

REBOOT HANDLING:
    The script automatically handles reboots during the update stage.
    State is preserved via systemd service and state files.
    No manual intervention required after reboots.

LOGS:
    Setup logs: $LOG_FILE
    State file: $STATE_FILE
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
    local resume_after_reboot=false
    local test_mode=false
    local show_status=false
    local cleanup_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stage)
                target_stage="$2"
                shift 2
                ;;
            --resume-after-reboot)
                resume_after_reboot=true
                shift
                ;;
            --banner-text)
                banner_text="$2"
                shift 2
                ;;
            --zabbix-version)
                zabbix_version="$2"
                shift 2
                ;;
            --ssh-host)
                ssh_host="$2"
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
                log_error "Unknown parameter: $1"
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
        # Resume after reboot
        if next_stage=$(check_reboot_flag); then
            target_stage="$next_stage"
            clear_reboot_flag
            log_info "Resuming after reboot: $target_stage"
        else
            log_error "Resume requested but no reboot flag found"
            exit 1
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
            stage_post_reboot && stage_zabbix_install "$zabbix_version" && stage_zabbix_configure && stage_tunnel_setup && stage_complete
            ;;
        "$STAGE_ZABBIX_INSTALL")
            stage_zabbix_install "$zabbix_version" && stage_zabbix_configure && stage_tunnel_setup && stage_complete
            ;;
        "$STAGE_ZABBIX_CONFIGURE")
            stage_zabbix_configure && stage_tunnel_setup && stage_complete
            ;;
        "$STAGE_TUNNEL_SETUP")
            stage_tunnel_setup && stage_complete
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
