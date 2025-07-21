#!/bin/bash
#
# Virtualizor Recipe: Direct Download & Execute
# Author: Zabbix Monitor Project
#

set -euo pipefail

# =============================================================================
# CONFIGURATION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
# =============================================================================

ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ YOUR monitoring server
SSH_TUNNEL_PORT="2847"                           # ⚠️ YOUR unique SSH port  
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ YOUR unique username
ZABBIX_VERSION="6.4"                             # Zabbix version to install
ZABBIX_SERVER_PORT="10051"                       # Zabbix server port

# =============================================================================
# EXECUTION LOGIC
# =============================================================================

SCRIPT_URL="https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"
SCRIPT_PATH="/tmp/virtualizor-server-setup.sh"
LOG_FILE="/var/log/virtualizor-recipe.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Validate configuration (prevent using placeholder values)
if [[ "$ZABBIX_SERVER_DOMAIN" == "monitor.yourcompany.com" ]]; then
    log "❌ ERROR: Must update ZABBIX_SERVER_DOMAIN with your actual server"
    exit 1
fi

# Wait for network
log "🌐 Waiting for network..."
for i in {1..30}; do
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "✅ Network ready"
        break
    fi
    [[ $i -eq 30 ]] && { log "❌ Network timeout"; exit 1; }
    sleep 2
done

# Download script
log "� Downloading setup script..."
if ! wget -q --timeout=30 "$SCRIPT_URL" -O "$SCRIPT_PATH"; then
    log "❌ Download failed"
    exit 1
fi

chmod +x "$SCRIPT_PATH"
log "✅ Script ready"

# Execute with configuration
log "🚀 Starting setup: $ZABBIX_SERVER_DOMAIN:$SSH_TUNNEL_PORT ($SSH_TUNNEL_USER)"

if "$SCRIPT_PATH" \
    --ssh-host "$ZABBIX_SERVER_DOMAIN" \
    --ssh-port "$SSH_TUNNEL_PORT" \
    --ssh-user "$SSH_TUNNEL_USER" \
    --zabbix-version "$ZABBIX_VERSION" \
    --zabbix-server-port "$ZABBIX_SERVER_PORT"; then
    
    log "✅ Setup completed successfully"
    log "📋 Configured: $SSH_TUNNEL_USER@$ZABBIX_SERVER_DOMAIN:$SSH_TUNNEL_PORT"
else
    log "❌ Setup failed (exit code $?)"
    exit 1
fi

log "🎉 Virtualizor recipe completed!"
