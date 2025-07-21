#!/bin/bash
#
# Virtualizor Recipe: Dynamic Configuration with Runtime Script Modification
# This recipe downloads the script, injects your configuration values, and executes it
# Perfect for Virtualizor automated server provisioning where servers don't exist yet
# Author: Zabbix Monitor Project

set -euo pipefail

# =============================================================================
# CONFIGURATION SECTION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
# =============================================================================

# ⚠️ CUSTOMIZE THESE VALUES FOR YOUR INFRASTRUCTURE
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ YOUR monitoring server
SSH_TUNNEL_PORT="2847"                           # ⚠️ YOUR unique SSH port
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ YOUR unique username
ZABBIX_VERSION="6.4"                             # Zabbix version to install
ZABBIX_SERVER_PORT="10051"                       # Zabbix server port

# =============================================================================
# RECIPE EXECUTION LOGIC - DO NOT MODIFY BELOW THIS LINE
# =============================================================================

RECIPE_LOG="/var/log/virtualizor-recipe.log"
SCRIPT_URL="https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"
TEMP_SCRIPT="/tmp/virtualizor-server-setup.sh"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RECIPE_LOG"
}

# Validate configuration values (prevent using examples in production)
validate_configuration() {
    local has_errors=false
    
    log_message "🔍 Validating configuration values..."
    
    # Check for example/default values (SECURITY RISK)
    if [[ "$ZABBIX_SERVER_DOMAIN" == "monitor.yourcompany.com" ]]; then
        log_message "❌ ERROR: Using example domain '$ZABBIX_SERVER_DOMAIN'"
        log_message "   You must edit this recipe and set your actual monitoring server!"
        has_errors=true
    fi
    
    if [[ "$has_errors" == "true" ]]; then
        log_message ""
        log_message "🔧 RECIPE CONFIGURATION REQUIRED:"
        log_message "   Edit this recipe file and update the CONFIGURATION SECTION"
        log_message "   with your actual server details before uploading to Virtualizor."
        exit 1
    fi
    
    log_message "✅ Configuration validation passed"
}

# Wait for network connectivity
wait_for_network() {
    log_message "🌐 Waiting for network connectivity..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log_message "✅ Network connectivity confirmed"
            return 0
        fi
        
        log_message "   Attempt $attempt/$max_attempts - Network not ready, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_message "❌ Network connectivity failed after $max_attempts attempts"
    return 1
}

# Download the master script
download_script() {
    log_message "📥 Downloading master setup script from GitHub..."
    
    if ! curl -fsSL --connect-timeout 30 --max-time 120 "$SCRIPT_URL" -o "$TEMP_SCRIPT"; then
        log_message "❌ Failed to download script from $SCRIPT_URL"
        
        # Fallback: try wget if curl fails
        log_message "🔄 Trying wget as fallback..."
        if ! wget --timeout=30 --tries=3 -q "$SCRIPT_URL" -O "$TEMP_SCRIPT"; then
            log_message "❌ Both curl and wget failed to download script"
            exit 1
        fi
    fi
    
    if [[ ! -f "$TEMP_SCRIPT" ]] || [[ ! -s "$TEMP_SCRIPT" ]]; then
        log_message "❌ Downloaded script is empty or missing"
        exit 1
    fi
    
    chmod +x "$TEMP_SCRIPT"
    log_message "✅ Script downloaded and made executable"
}

# Inject configuration values into the downloaded script
configure_script() {
    log_message "⚙️ Injecting configuration values into script..."
    
    # Create a backup of original script
    cp "$TEMP_SCRIPT" "${TEMP_SCRIPT}.original"
    
    # Replace configuration values in the script using sed
    sed -i "s|DEFAULT_HOME_SERVER_IP=.*|DEFAULT_HOME_SERVER_IP=\"$ZABBIX_SERVER_DOMAIN\"|g" "$TEMP_SCRIPT"
    sed -i "s|SSH_TUNNEL_PORT=.*|SSH_TUNNEL_PORT=\"$SSH_TUNNEL_PORT\"|g" "$TEMP_SCRIPT"  
    sed -i "s|SSH_TUNNEL_USER=.*|SSH_TUNNEL_USER=\"$SSH_TUNNEL_USER\"|g" "$TEMP_SCRIPT"
    sed -i "s|ZABBIX_VERSION=.*|ZABBIX_VERSION=\"$ZABBIX_VERSION\"|g" "$TEMP_SCRIPT"
    sed -i "s|ZABBIX_SERVER_PORT=.*|ZABBIX_SERVER_PORT=\"$ZABBIX_SERVER_PORT\"|g" "$TEMP_SCRIPT"
    
    # Verify changes were applied
    if grep -q "$ZABBIX_SERVER_DOMAIN" "$TEMP_SCRIPT"; then
        log_message "✅ Configuration values successfully injected into script"
    else
        log_message "⚠️  Warning: Configuration injection may not have worked properly"
        log_message "   Script will run with built-in defaults and environment variables"
    fi
}

# Execute the configured script
execute_script() {
    log_message "🚀 Starting configured server setup..."
    log_message "   Server: $ZABBIX_SERVER_DOMAIN"
    log_message "   SSH Port: $SSH_TUNNEL_PORT" 
    log_message "   SSH User: $SSH_TUNNEL_USER"
    log_message "   Zabbix Version: $ZABBIX_VERSION"
    
    # Export environment variables as backup configuration method
    export ZABBIX_SERVER_DOMAIN="$ZABBIX_SERVER_DOMAIN"
    export SSH_TUNNEL_PORT="$SSH_TUNNEL_PORT"
    export SSH_TUNNEL_USER="$SSH_TUNNEL_USER"
    export ZABBIX_VERSION="$ZABBIX_VERSION"
    export ZABBIX_SERVER_PORT="$ZABBIX_SERVER_PORT"
    
    # Execute the script with configuration parameters
    if "$TEMP_SCRIPT" \
        --ssh-host "$ZABBIX_SERVER_DOMAIN" \
        --ssh-port "$SSH_TUNNEL_PORT" \
        --ssh-user "$SSH_TUNNEL_USER" \
        --zabbix-version "$ZABBIX_VERSION" \
        --zabbix-server-port "$ZABBIX_SERVER_PORT"; then
        
        log_message "✅ Server setup completed successfully"
        log_message "📋 Setup summary:"
        log_message "   - Monitoring Server: $ZABBIX_SERVER_DOMAIN"
        log_message "   - SSH Tunnel Port: $SSH_TUNNEL_PORT"
        log_message "   - SSH Tunnel User: $SSH_TUNNEL_USER"
        log_message "   - Zabbix Version: $ZABBIX_VERSION"
        
    else
        log_message "❌ Server setup failed - check logs for details"
        log_message "📋 Debug info available in:"
        log_message "   - Recipe log: $RECIPE_LOG"
        log_message "   - Setup logs: /var/log/zabbix-scripts/"
        exit 1
    fi
}

# Cleanup temporary files
cleanup() {
    log_message "🧹 Cleaning up temporary files..."
    rm -f "$TEMP_SCRIPT" "${TEMP_SCRIPT}.original" 2>/dev/null || true
    log_message "✅ Cleanup completed"
}

# Main execution flow
main() {
    log_message "🎯 Starting Virtualizor Recipe: Dynamic Configuration"
    log_message "   Recipe: Direct Download with Runtime Configuration"
    log_message "   Author: Zabbix Monitor Project"
    
    validate_configuration
    wait_for_network
    download_script
    configure_script
    execute_script
    cleanup
    
    log_message "🎉 Virtualizor recipe completed successfully!"
    log_message "   Server is now ready for monitoring"
}

# Execute main function
main "$@"
