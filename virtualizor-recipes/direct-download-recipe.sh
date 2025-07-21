#!/bin/bash
#
# Virtualizor Recipe: Direct Download with Dynamic Configuration
# This recipe downloads the latest script and executes with custom configuration
# Supports all major Linux distributions with automatic OS detection
# IMPORTANT: Customize the configuration section below for your infrastructure
#

set -euo pipefail

# ====================================================================
# CONFIGURATION SECTION - CUSTOMIZE FOR YOUR INFRASTRUCTURE
# ====================================================================

# CRITICAL: Replace these default values with YOUR infrastructure details
# Method 1: Environment Variables (recommended for Virtualizor)
export ZABBIX_SERVER_DOMAIN="your-monitor-server.example.com"  # YOUR server domain/IP
export SSH_TUNNEL_PORT="2022"                                  # YOUR unique SSH port
export SSH_TUNNEL_USER="zabbix-user"                          # YOUR unique SSH username
export ZABBIX_SERVER_PORT="10051"                             # Usually 10051
export ZABBIX_VERSION="6.4"                                   # Zabbix version

# SECURITY: Ensure these values are unique and not predictable
# - Use YOUR domain/IP instead of examples
# - Use non-standard SSH ports (avoid 22, 2222, 20202)  
# - Use unique usernames (avoid 'zabbix', 'zabbixssh', 'monitoring')

# ====================================================================
# RECIPE EXECUTION LOGIC (DO NOT MODIFY BELOW THIS LINE)
# ====================================================================

# Virtualizor Recipe Configuration
SCRIPT_URL="https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"
SCRIPT_PATH="/tmp/virtualizor-server-setup.sh"
LOG_FILE="/var/log/virtualizor-recipe.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== Virtualizor Recipe Started ==="
log_message "OS Detection: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
log_message "Architecture: $(uname -m)"

# Detect package manager and install wget if missing
detect_and_install_wget() {
    log_message "Checking for wget availability..."
    
    if command -v wget >/dev/null 2>&1; then
        log_message "wget is already available"
        return 0
    fi
    
    log_message "wget not found, attempting to install..."
    
    # Detect OS family and package manager
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                log_message "Detected Debian/Ubuntu - using apt"
                apt-get update -qq >/dev/null 2>&1 || true
                apt-get install -y wget >/dev/null 2>&1
                ;;
            rhel|centos|almalinux|rocky|fedora)
                log_message "Detected RHEL family - using yum/dnf"
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y wget >/dev/null 2>&1
                else
                    yum install -y wget >/dev/null 2>&1
                fi
                ;;
            *)
                log_message "Unknown OS, trying multiple package managers..."
                # Try common package managers
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update -qq >/dev/null 2>&1 && apt-get install -y wget >/dev/null 2>&1
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y wget >/dev/null 2>&1
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y wget >/dev/null 2>&1
                elif command -v zypper >/dev/null 2>&1; then
                    zypper install -y wget >/dev/null 2>&1
                elif command -v apk >/dev/null 2>&1; then
                    apk add wget >/dev/null 2>&1
                else
                    log_message "ERROR: No supported package manager found"
                    return 1
                fi
                ;;
        esac
    fi
    
    # Verify wget is now available
    if command -v wget >/dev/null 2>&1; then
        log_message "wget installed successfully"
        return 0
    else
        log_message "ERROR: Failed to install wget"
        return 1
    fi
}

log_message "=== Virtualizor Recipe Started ==="

# Install wget if missing
detect_and_install_wget || {
    log_message "ERROR: Failed to ensure wget availability"
    exit 1
}

# Enhanced network connectivity check with multiple methods
wait_for_network() {
    log_message "Waiting for network connectivity..."
    local max_attempts=60  # 2 minutes total
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Try multiple connectivity tests
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
           ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || \
           wget --timeout=5 --tries=1 -q --spider "$SCRIPT_URL" 2>/dev/null; then
            log_message "Network connectivity confirmed"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 10)) -eq 0 ]; then
            log_message "Still waiting for network... (attempt $attempt/$max_attempts)"
        fi
        sleep 2
    done
    
    log_message "ERROR: Network connectivity timeout after $max_attempts attempts"
    return 1
}

# Wait for network with comprehensive testing
wait_for_network || {
    log_message "ERROR: Network connectivity failed"
    exit 1
}

# Download the script with retry logic
download_script() {
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        log_message "Downloading setup script (attempt $((retry + 1))/$max_retries): $SCRIPT_URL"
        
        if wget -O "$SCRIPT_PATH" "$SCRIPT_URL" >/dev/null 2>&1; then
            # Verify download was successful and file is not empty
            if [ -s "$SCRIPT_PATH" ]; then
                log_message "Script downloaded successfully ($(wc -c < "$SCRIPT_PATH") bytes)"
                return 0
            else
                log_message "Downloaded file is empty, retrying..."
            fi
        else
            log_message "Download failed, retrying..."
        fi
        
        retry=$((retry + 1))
        [ $retry -lt $max_retries ] && sleep 5
    done
    
    log_message "ERROR: Failed to download script after $max_retries attempts"
    return 1
}

# Download with retry logic
download_script || {
    log_message "ERROR: Script download failed"
    exit 1
}

# Make it executable and validate
chmod +x "$SCRIPT_PATH"
log_message "Script made executable"

# Basic script validation
if ! bash -n "$SCRIPT_PATH" 2>/dev/null; then
    log_message "ERROR: Downloaded script has syntax errors"
    exit 1
fi
log_message "Script syntax validation passed"

# Configuration validation for security
validate_configuration() {
    local warnings=0
    
    if [[ "$ZABBIX_SERVER_DOMAIN" == *"example.com"* ]] || [[ "$ZABBIX_SERVER_DOMAIN" == "your-monitor-server"* ]]; then
        log_message "WARNING: Using example domain - Update ZABBIX_SERVER_DOMAIN with your real server"
        warnings=$((warnings + 1))
    fi
    
    if [ "$SSH_TUNNEL_PORT" = "22" ] || [ "$SSH_TUNNEL_PORT" = "2222" ] || [ "$SSH_TUNNEL_PORT" = "20202" ]; then
        log_message "WARNING: Using common SSH port ($SSH_TUNNEL_PORT) - Consider using unique port for security"
        warnings=$((warnings + 1))
    fi
    
    if [[ "$SSH_TUNNEL_USER" == *"zabbix"* ]] || [ "$SSH_TUNNEL_USER" = "monitoring" ]; then
        log_message "WARNING: Using predictable username ($SSH_TUNNEL_USER) - Consider using unique username"
        warnings=$((warnings + 1))
    fi
    
    if [ $warnings -gt 0 ]; then
        log_message "SECURITY NOTICE: $warnings configuration warnings found"
        log_message "For production use, customize configuration values in recipe file"
    fi
}

# Validate configuration
validate_configuration

# Execute the script with runtime configuration
log_message "Starting server setup with configuration:"
log_message "  Server: $ZABBIX_SERVER_DOMAIN"
log_message "  SSH Port: $SSH_TUNNEL_PORT" 
log_message "  SSH User: $SSH_TUNNEL_USER"
log_message "  Zabbix Version: $ZABBIX_VERSION"

if "$SCRIPT_PATH" --ssh-host "$ZABBIX_SERVER_DOMAIN" \
                  --ssh-port "$SSH_TUNNEL_PORT" \
                  --ssh-user "$SSH_TUNNEL_USER" \
                  --zabbix-version "$ZABBIX_VERSION" \
                  --zabbix-server-port "$ZABBIX_SERVER_PORT"; then
    log_message "=== Server setup completed successfully ==="
    log_message "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    log_message "Zabbix monitoring configured for: $ZABBIX_SERVER_DOMAIN:$ZABBIX_SERVER_PORT"
    log_message "SSH tunnel configured for: $SSH_TUNNEL_USER@$ZABBIX_SERVER_DOMAIN:$SSH_TUNNEL_PORT"
    log_message "SSH public key available in: /root/zabbix_tunnel_public_key.txt"
else
    exit_code=$?
    log_message "ERROR: Server setup failed with exit code $exit_code"
    log_message "Check setup logs: /var/log/zabbix-scripts/virtualizor-server-setup-*.log"
    exit $exit_code
fi

log_message "=== Virtualizor Recipe Completed Successfully ==="
