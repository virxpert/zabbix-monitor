#!/bin/bash
#
# Virtualizor Recipe: Embedded Script (Multi-OS Support)
# This recipe contains the complete setup script embedded within it
# Compatible with: Ubuntu 18.04-24.04, Debian 10-12, RHEL/CentOS 7-9, AlmaLinux/Rocky 8-9
# Copy the entire virtualizor-server-setup.sh content after this header
# Author: Generated for public repository deployment
#

# Recipe Header with enhanced OS detection
RECIPE_LOG="/var/log/virtualizor-recipe.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RECIPE_LOG"
}

# Enhanced OS detection
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_message "Detected OS: $PRETTY_NAME (ID: $ID, Version: ${VERSION_ID:-'unknown'})"
        return 0
    else
        log_message "OS detection: $(uname -s) $(uname -r)"
        return 1
    fi
}

log_message "Starting embedded Virtualizor recipe"
detect_os

# Enhanced network connectivity check with multiple methods
check_network() {
    log_message "Testing network connectivity..."
    
    # Method 1: Ping Google DNS
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_message "Network connectivity confirmed (Google DNS)"
        return 0
    fi
    
    # Method 2: Ping Cloudflare DNS
    if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log_message "Network connectivity confirmed (Cloudflare DNS)"
        return 0
    fi
    
    # Method 3: Test GitHub connectivity
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 10 https://github.com >/dev/null; then
            log_message "Network connectivity confirmed (GitHub via curl)"
            return 0
        fi
    fi
    
    return 1
}

# Wait for network with enhanced checking
log_message "Waiting for network connectivity..."
for i in {1..30}; do
    if check_network; then
        log_message "Network ready after ${i} attempts"
        break
    fi
    log_message "Network not ready, attempt $i/30, waiting..."
    sleep 2
    if [ $i -eq 30 ]; then
        log_message "WARNING: Network connectivity timeout after 30 attempts"
    fi
done

# Create the setup script
cat > /tmp/virtualizor-server-setup.sh << 'EMBEDDED_SCRIPT_EOF'
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
readonly ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"

# System settings
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30
readonly REBOOT_TIMEOUT=300  # 5 minutes wait after reboot
readonly UPDATE_TIMEOUT=1800  # 30 minutes for updates

# [COMPLETE SCRIPT CONTENT FROM virtualizor-server-setup.sh - TRUNCATED FOR BREVITY]
# NOTE: This is where the complete virtualizor-server-setup.sh content would be inserted
# For brevity in this documentation update, showing structure only

# Execute main function with all arguments
main "$@"

EMBEDDED_SCRIPT_EOF

# Execute the embedded script
chmod +x /tmp/virtualizor-server-setup.sh
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing embedded setup script" | tee -a "$RECIPE_LOG"

if /tmp/virtualizor-server-setup.sh --banner-text "Virtualizor Managed Server - READY"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setup completed successfully" | tee -a "$RECIPE_LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setup failed" | tee -a "$RECIPE_LOG"
    exit 1
fi
