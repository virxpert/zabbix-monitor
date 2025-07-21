#!/bin/bash
#
# Virtualizor Recipe: Cloud-Init Compatible with Multi-OS Support
# This recipe is designed to work with cloud-init and systemd across all Linux distributions
# Supports Ubuntu, Debian, RHEL, CentOS, AlmaLinux, Rocky Linux, and more
#

# Cloud-init compatible header
# This section can be used in cloud-init user-data as well

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This recipe must run as root"
    exit 1
fi

# Detect OS for logging
detect_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME (ID: $ID, Version: $VERSION_ID)"
    else
        echo "$(uname -s) $(uname -r)"
    fi
}

echo "Starting Virtualizor Cloud-Init compatible setup on: $(detect_os_info)"

# Create a systemd service for first-boot execution
cat > /etc/systemd/system/virtualizor-first-boot.service << 'EOF'
[Unit]
Description=Virtualizor First Boot Setup
After=network-online.target
Wants=network-online.target
Before=getty@tty1.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/virtualizor-first-boot.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF

# Create the first-boot script with enhanced OS detection and error handling
cat > /usr/local/bin/virtualizor-first-boot.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/virtualizor-first-boot.log"
SCRIPT_URL="https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Enhanced OS detection
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_message "Detected OS: $PRETTY_NAME (ID: $ID, Version: ${VERSION_ID:-'unknown'})"
    else
        log_message "OS detection: $(uname -s) $(uname -r)"
    fi
}

# Install wget if not available (multi-OS support)
ensure_wget() {
    if command -v wget >/dev/null 2>&1; then
        log_message "wget is available"
        return 0
    fi
    
    log_message "Installing wget..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                apt-get update -qq && apt-get install -y wget
                ;;
            rhel|centos|almalinux|rocky|fedora)
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y wget
                else
                    yum install -y wget
                fi
                ;;
            opensuse*|sles)
                zypper install -y wget
                ;;
            alpine)
                apk add wget
                ;;
            *)
                log_message "Unknown OS, trying common package managers..."
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update -qq && apt-get install -y wget
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y wget
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y wget
                else
                    log_message "ERROR: Cannot install wget - no supported package manager"
                    return 1
                fi
                ;;
        esac
    fi
    
    if command -v wget >/dev/null 2>&1; then
        log_message "wget installed successfully"
        return 0
    else
        log_message "ERROR: Failed to install wget"
        return 1
    fi
}

log_message "=== Virtualizor First Boot Setup Started ==="
detect_os
ensure_wget || exit 1

# Wait for network
log_message "Waiting for network connectivity..."
for i in {1..60}; do
    if wget --timeout=5 --tries=1 -q --spider "$SCRIPT_URL"; then
        log_message "Network and script URL accessible"
        break
    fi
    if [ $i -eq 60 ]; then
        log_message "ERROR: Network or script URL timeout"
        exit 1
    fi
    sleep 5
done

# Download and execute
log_message "Downloading setup script..."
if wget -O /tmp/setup.sh "$SCRIPT_URL"; then
    chmod +x /tmp/setup.sh
    log_message "Executing setup script..."
    if /tmp/setup.sh --banner-text "Virtualizor Managed Server - READY"; then
        log_message "Setup completed successfully"
        # Disable this service so it doesn't run again
        systemctl disable virtualizor-first-boot.service
        rm -f /etc/systemd/system/virtualizor-first-boot.service
        systemctl daemon-reload
    else
        log_message "Setup failed"
        exit 1
    fi
else
    log_message "Failed to download setup script"
    exit 1
fi

log_message "=== First Boot Setup Complete ==="
EOF

# Make the script executable
chmod +x /usr/local/bin/virtualizor-first-boot.sh

# Enable the service
systemctl daemon-reload
systemctl enable virtualizor-first-boot.service

echo "Virtualizor first-boot service configured successfully"
echo "The setup will run automatically on next boot"
