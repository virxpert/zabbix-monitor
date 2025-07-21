#!/bin/bash
#
# Virtualizor Recipe: Direct Download and Execute
# This recipe downloads the latest script from GitHub and executes it
# Supports all major Linux distributions with automatic OS detection
# Place this content in your Virtualizor recipe configuration
#

set -euo pipefail

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

# Execute the script with default settings for multi-OS compatibility
log_message "Starting server setup with OS auto-detection..."
if "$SCRIPT_PATH" --banner-text "Virtualizor Managed Server - READY"; then
    log_message "=== Server setup completed successfully ==="
    log_message "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    log_message "Zabbix monitoring configured and ready"
    log_message "SSH tunnel service configured (requires key setup)"
else
    exit_code=$?
    log_message "ERROR: Server setup failed with exit code $exit_code"
    log_message "Check setup logs: /var/log/zabbix-scripts/virtualizor-server-setup-*.log"
    exit $exit_code
fi

log_message "=== Virtualizor Recipe Completed Successfully ==="
