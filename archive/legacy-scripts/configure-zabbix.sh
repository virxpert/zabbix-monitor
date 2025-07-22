#!/bin/bash
# ====================================================================
# Script: configure_zabbix.sh - Zabbix Agent Configuration with SSH Tunnel for Virtualizor Provisioning
# Usage: ./configure_zabbix.sh [--server IP] [--ssh-host HOST] [--ssh-user USER] [--test]
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
readonly DEFAULT_HOME_SERVER_IP="monitor.cloudgeeks.in"
readonly DEFAULT_HOME_SERVER_SSH_PORT=20202
readonly DEFAULT_ZABBIX_SERVER_PORT=10051
readonly DEFAULT_SSH_USER="zabbixssh"
readonly DEFAULT_SSH_KEY="/root/.ssh/zabbix_tunnel_key"
readonly DEFAULT_ADMIN_USER="root"
readonly DEFAULT_ADMIN_KEY="/root/.ssh/id_rsa"
readonly ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"
readonly TUNNEL_SERVICE="/etc/systemd/system/zabbix-tunnel.service"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30

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

validate_zabbix_installed() {
    if [ ! -f "$ZBX_CONF" ]; then
        log_error "Zabbix agent configuration file not found: $ZBX_CONF"
        log_error "Please install Zabbix agent first using install_zabbix_agent_virtualizor.sh"
        return 1
    fi
    
    if ! command -v zabbix_agentd >/dev/null 2>&1; then
        log_error "Zabbix agent binary not found"
        return 1
    fi
    
    log_info "Zabbix agent installation validated"
    return 0
}

validate_ssh_connectivity() {
    local ssh_host="$1"
    local ssh_port="$2"
    local ssh_user="$3"
    local ssh_key="$4"
    
    log_info "Testing SSH connectivity to $ssh_user@$ssh_host:$ssh_port"
    
    # Check if SSH key exists
    if [ ! -f "$ssh_key" ]; then
        log_error "SSH key file not found: $ssh_key"
        return 1
    fi
    
    # Set proper permissions on SSH key
    chmod 600 "$ssh_key"
    
    # Test SSH connectivity with timeout
    for attempt in $(seq 1 $MAX_RETRIES); do
        if ssh -i "$ssh_key" \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=10 \
               -p "$ssh_port" \
               "$ssh_user@$ssh_host" \
               "echo 'SSH connectivity test successful'" >/dev/null 2>&1; then
            log_info "SSH connectivity confirmed"
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "SSH connectivity failed (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "Failed to establish SSH connectivity after $MAX_RETRIES attempts"
    return 3
}

generate_ssh_key() {
    local ssh_key="$1"
    local key_comment="zabbix-tunnel-$(hostname)-$(date +%Y%m%d)"
    
    log_info "Generating SSH key for tunnel: $ssh_key"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$ssh_key")"
    
    # Generate key without passphrase for automation
    if ssh-keygen -t rsa -b 4096 -f "$ssh_key" -N "" -C "$key_comment" >/dev/null 2>&1; then
        chmod 600 "$ssh_key"
        chmod 644 "${ssh_key}.pub"
        log_info "SSH key generated successfully"
        log_info "Public key location: ${ssh_key}.pub"
        log_warn "IMPORTANT: Copy the following public key to the remote server's authorized_keys file:"
        cat "${ssh_key}.pub"
        return 0
    else
        log_error "Failed to generate SSH key"
        return 1
    fi
}

configure_zabbix_agent() {
    local zabbix_hostname="$1"
    
    log_info "Configuring Zabbix agent for tunnel connectivity"
    
    # Backup original configuration
    local backup_conf="${ZBX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$ZBX_CONF" "$backup_conf"; then
        log_error "Failed to create backup of configuration file"
        return 1
    fi
    log_info "Configuration backup created: $backup_conf"
    
    # Configure for local tunnel connection
    log_info "Configuring Zabbix agent to connect via local tunnel (127.0.0.1)"
    
    if ! sed -i "s/^Server=.*/Server=127.0.0.1/" "$ZBX_CONF"; then
        log_error "Failed to update Server setting"
        return 1
    fi
    
    if ! sed -i "s/^ServerActive=.*/ServerActive=127.0.0.1/" "$ZBX_CONF"; then
        log_error "Failed to update ServerActive setting"
        return 1
    fi
    
    if ! sed -i "s/^Hostname=.*/Hostname=${zabbix_hostname}/" "$ZBX_CONF"; then
        log_error "Failed to update Hostname setting"
        return 1
    fi
    
    # Enable debug logging for troubleshooting
    log_info "Enabling debug logging"
    if grep -q "^# DebugLevel=" "$ZBX_CONF"; then
        sed -i "s/^# DebugLevel=.*/DebugLevel=4/" "$ZBX_CONF"
    elif grep -q "^DebugLevel=" "$ZBX_CONF"; then
        sed -i "s/^DebugLevel=.*/DebugLevel=4/" "$ZBX_CONF"
    else
        echo "DebugLevel=4" >> "$ZBX_CONF"
    fi
    
    # Validate configuration
    if ! zabbix_agentd -t -c "$ZBX_CONF" >/dev/null 2>&1; then
        log_error "Zabbix agent configuration validation failed"
        log_info "Restoring backup configuration"
        cp "$backup_conf" "$ZBX_CONF" || true
        return 1
    fi
    
    log_info "Zabbix agent configuration validation passed"
    
    # Restart Zabbix agent
    if ! systemctl enable zabbix-agent; then
        log_error "Failed to enable Zabbix agent service"
        return 1
    fi
    
    if ! systemctl restart zabbix-agent; then
        log_error "Failed to restart Zabbix agent service"
        return 1
    fi
    
    # Verify service is running
    sleep 3
    if ! systemctl is-active zabbix-agent >/dev/null 2>&1; then
        log_error "Zabbix agent service is not running"
        systemctl status zabbix-agent --no-pager || true
        return 1
    fi
    
    log_info "Zabbix agent configured and running successfully"
    return 0
}

create_tunnel_service() {
    local home_server_ip="$1"
    local home_server_ssh_port="$2"
    local zabbix_server_port="$3"
    local ssh_user="$4"
    local ssh_key="$5"
    
    log_info "Creating systemd service for SSH reverse tunnel"
    
    # Create systemd service file
    cat > "$TUNNEL_SERVICE" << EOF
[Unit]
Description=Persistent SSH Reverse Tunnel to Zabbix Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 30
ExecStart=/usr/bin/ssh -i ${ssh_key} \\
    -o ExitOnForwardFailure=yes \\
    -o ServerAliveInterval=60 \\
    -o ServerAliveCountMax=3 \\
    -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o BatchMode=yes \\
    -N -R ${zabbix_server_port}:localhost:${zabbix_server_port} \\
    -p ${home_server_ssh_port} \\
    ${ssh_user}@${home_server_ip}
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    if [ ! -f "$TUNNEL_SERVICE" ]; then
        log_error "Failed to create tunnel service file"
        return 1
    fi
    
    log_info "Tunnel service file created: $TUNNEL_SERVICE"
    
    # Reload systemd and enable service
    if ! systemctl daemon-reload; then
        log_error "Failed to reload systemd daemon"
        return 1
    fi
    
    if ! systemctl enable zabbix-tunnel; then
        log_error "Failed to enable tunnel service"
        return 1
    fi
    
    log_info "Tunnel service enabled successfully"
    return 0
}

start_tunnel_service() {
    log_info "Starting SSH tunnel service"
    
    # Stop service if already running
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1; then
        log_info "Stopping existing tunnel service"
        systemctl stop zabbix-tunnel || true
        sleep 5
    fi
    
    # Start the service
    if ! systemctl start zabbix-tunnel; then
        log_error "Failed to start tunnel service"
        return 1
    fi
    
    # Wait a moment and check status
    sleep 10
    
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1; then
        log_info "SSH tunnel service started successfully"
        return 0
    else
        log_error "SSH tunnel service failed to start"
        log_info "Service status:"
        systemctl status zabbix-tunnel --no-pager || true
        return 1
    fi
}

# ====================================================================
# SSH USER MANAGEMENT FUNCTIONS
# ====================================================================
create_remote_ssh_user() {
    local ssh_host="$1"
    local ssh_port="$2"
    local admin_user="$3"
    local admin_key="$4"
    local tunnel_user="$5"
    local tunnel_key_pub="$6"
    
    log_info "Creating SSH tunnel user on remote server: $tunnel_user@$ssh_host"
    
    # Validate admin SSH key exists
    if [ ! -f "$admin_key" ]; then
        log_error "Admin SSH key not found: $admin_key"
        log_error "Need admin access to create tunnel user on remote server"
        return 1
    fi
    
    # Test admin connectivity first
    log_info "Testing admin SSH connectivity to $admin_user@$ssh_host:$ssh_port"
    if ! ssh -i "$admin_key" \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -o ConnectTimeout=10 \
             -p "$ssh_port" \
             "$admin_user@$ssh_host" \
             "echo 'Admin access confirmed'" >/dev/null 2>&1; then
        log_error "Cannot establish admin SSH connection to create tunnel user"
        return 3
    fi
    
    log_info "Admin SSH connectivity confirmed, proceeding with user creation"
    
    # Create remote script for user management
    local remote_script=$(cat << 'REMOTE_SCRIPT'
#!/bin/bash
set -euo pipefail

TUNNEL_USER="$1"
TUNNEL_KEY_PUB="$2"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating tunnel user: $TUNNEL_USER"

# Check if user already exists
if id "$TUNNEL_USER" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] User $TUNNEL_USER already exists"
else
    # Create user with restricted shell for security
    if command -v useradd >/dev/null 2>&1; then
        useradd -r -s /bin/bash -m -d "/home/$TUNNEL_USER" -c "Zabbix SSH Tunnel User" "$TUNNEL_USER"
    elif command -v adduser >/dev/null 2>&1; then
        adduser --system --shell /bin/bash --home "/home/$TUNNEL_USER" --gecos "Zabbix SSH Tunnel User" "$TUNNEL_USER"
    else
        echo "ERROR: No user creation command found (useradd/adduser)"
        exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] User $TUNNEL_USER created successfully"
fi

# Create .ssh directory with proper permissions
USER_HOME=$(getent passwd "$TUNNEL_USER" | cut -d: -f6)
SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chown "$TUNNEL_USER:$TUNNEL_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Add public key to authorized_keys with tunnel restrictions
TUNNEL_RESTRICTIONS='command="echo '\''Tunnel connection only'\''",no-agent-forwarding,no-X11-forwarding,no-pty'

if [ ! -f "$AUTH_KEYS" ]; then
    touch "$AUTH_KEYS"
fi

# Check if key already exists
if ! grep -q "$TUNNEL_KEY_PUB" "$AUTH_KEYS" 2>/dev/null; then
    echo "$TUNNEL_RESTRICTIONS $TUNNEL_KEY_PUB" >> "$AUTH_KEYS"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Public key added to authorized_keys"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Public key already exists in authorized_keys"
fi

chown "$TUNNEL_USER:$TUNNEL_USER" "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# Create tunnel user's SSH config for better security
SSH_CONFIG="$SSH_DIR/config"
cat > "$SSH_CONFIG" << 'SSH_CONFIG_END'
# Zabbix tunnel SSH client configuration
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
SSH_CONFIG_END

chown "$TUNNEL_USER:$TUNNEL_USER" "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH tunnel user setup completed successfully"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] User: $TUNNEL_USER"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Home: $USER_HOME"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH Dir: $SSH_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S")] Auth Keys: $AUTH_KEYS"
REMOTE_SCRIPT
)
    
    # Execute remote script via SSH
    log_info "Executing user creation script on remote server"
    if ssh -i "$admin_key" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -p "$ssh_port" \
           "$admin_user@$ssh_host" \
           "bash -s $tunnel_user '$tunnel_key_pub'" <<< "$remote_script"; then
        log_info "SSH tunnel user created successfully on remote server"
        return 0
    else
        log_error "Failed to create SSH tunnel user on remote server"
        return 1
    fi
}

validate_remote_ssh_user() {
    local ssh_host="$1"
    local ssh_port="$2"
    local tunnel_user="$3"
    local tunnel_key="$4"
    
    log_info "Validating SSH tunnel user access: $tunnel_user@$ssh_host"
    
    # Test tunnel user connectivity
    if ssh -i "$tunnel_key" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -p "$ssh_port" \
           "$tunnel_user@$ssh_host" \
           "echo 'Tunnel user access confirmed'" >/dev/null 2>&1; then
        log_info "SSH tunnel user validation successful"
        return 0
    else
        log_warn "SSH tunnel user validation failed - user may not be properly configured"
        return 1
    fi
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Zabbix Agent Configuration with SSH Tunnel for Virtualizor Provisioning

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --ssh-host HOST        Remote SSH server hostname (default: $DEFAULT_HOME_SERVER_IP)
    --ssh-port PORT        Remote SSH server port (default: $DEFAULT_HOME_SERVER_SSH_PORT)
    --ssh-user USER        SSH username for tunnel (default: $DEFAULT_SSH_USER)
    --ssh-key PATH         SSH private key path for tunnel (default: $DEFAULT_SSH_KEY)
    --admin-user USER      Admin SSH username for user creation (default: $DEFAULT_ADMIN_USER)
    --admin-key PATH       Admin SSH private key path (default: $DEFAULT_ADMIN_KEY)
    --zabbix-port PORT     Zabbix server port (default: $DEFAULT_ZABBIX_SERVER_PORT)
    --hostname NAME        Agent hostname (default: system hostname)
    --create-user          Create SSH tunnel user on remote server
    --generate-key         Generate new SSH key and exit
    --test                 Test mode - validate configuration without changes
    --help                 Show this help message

EXAMPLES:
    $0                                          # Use defaults (assumes user exists)
    $0 --create-user                           # Create tunnel user on remote server
    $0 --ssh-host tunnel.company.com           # Custom SSH server
    $0 --generate-key                          # Generate SSH key
    $0 --test                                  # Test configuration

VIRTUALIZOR INTEGRATION:
    This script configures Zabbix agent to connect through an SSH reverse tunnel.
    It can automatically create the required SSH user on the remote server.

USER CREATION PROCESS:
    1. Generate tunnel SSH key: $0 --generate-key
    2. Create remote tunnel user: $0 --create-user --admin-user root --admin-key /path/to/admin/key
    3. Run configuration: $0

MANUAL SETUP (if --create-user not used):
    1. Generate SSH key: $0 --generate-key
    2. Manually create user '$DEFAULT_SSH_USER' on remote server
    3. Copy public key to remote server's authorized_keys
    4. Run configuration: $0

LOGS:
    Configuration logs: $LOG_FILE
    Tunnel service logs: journalctl -u zabbix-tunnel

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local home_server_ip="$DEFAULT_HOME_SERVER_IP"
    local home_server_ssh_port="$DEFAULT_HOME_SERVER_SSH_PORT"
    local zabbix_server_port="$DEFAULT_ZABBIX_SERVER_PORT"
    local ssh_user="$DEFAULT_SSH_USER"
    local ssh_key="$DEFAULT_SSH_KEY"
    local admin_user="$DEFAULT_ADMIN_USER"
    local admin_key="$DEFAULT_ADMIN_KEY"
    local zabbix_hostname="$(hostname)"
    local create_user=false
    local generate_key=false
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh-host)
                home_server_ip="$2"
                shift 2
                ;;
            --ssh-port)
                home_server_ssh_port="$2"
                shift 2
                ;;
            --ssh-user)
                ssh_user="$2"
                shift 2
                ;;
            --ssh-key)
                ssh_key="$2"
                shift 2
                ;;
            --admin-user)
                admin_user="$2"
                shift 2
                ;;
            --admin-key)
                admin_key="$2"
                shift 2
                ;;
            --zabbix-port)
                zabbix_server_port="$2"
                shift 2
                ;;
            --hostname)
                zabbix_hostname="$2"
                shift 2
                ;;
            --create-user)
                create_user=true
                shift
                ;;
            --generate-key)
                generate_key=true
                shift
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
    log_info "Starting Zabbix agent configuration with SSH tunnel"
    log_info "Parameters: SSH=$ssh_user@$home_server_ip:$home_server_ssh_port, Zabbix Port=$zabbix_server_port, Hostname=$zabbix_hostname"
    
    validate_root
    
    # Generate key mode
    if [ "$generate_key" = true ]; then
        log_info "Generating SSH key for tunnel"
        generate_ssh_key "$ssh_key"
        log_info "Key generation completed. Use --create-user to set up remote user automatically."
        exit 0
    fi
    
    # Create user mode
    if [ "$create_user" = true ]; then
        log_info "Creating SSH tunnel user on remote server"
        
        # Validate tunnel SSH key exists
        if [ ! -f "$ssh_key" ]; then
            log_error "Tunnel SSH key not found: $ssh_key"
            log_error "Generate it first with: $0 --generate-key"
            exit 2
        fi
        
        # Get public key content
        if [ ! -f "${ssh_key}.pub" ]; then
            log_error "Public key not found: ${ssh_key}.pub"
            exit 2
        fi
        
        local public_key_content=$(cat "${ssh_key}.pub")
        
        create_remote_ssh_user "$home_server_ip" "$home_server_ssh_port" "$admin_user" "$admin_key" "$ssh_user" "$public_key_content" || exit $?
        
        # Validate the newly created user
        validate_remote_ssh_user "$home_server_ip" "$home_server_ssh_port" "$ssh_user" "$ssh_key" || {
            log_warn "User creation completed but validation failed. Manual verification may be needed."
        }
        
        log_info "SSH tunnel user creation completed successfully"
        log_info "You can now run the full configuration with: $0"
        exit 0
    fi
    
    create_lock_file
    trap cleanup EXIT
    
    validate_zabbix_installed || exit 2
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        log_info "SSH server: $ssh_user@$home_server_ip:$home_server_ssh_port"
        log_info "SSH key: $ssh_key"
        log_info "Admin user: $admin_user (for user creation)"
        log_info "Admin key: $admin_key"
        log_info "Zabbix port: $zabbix_server_port"
        log_info "Agent hostname: $zabbix_hostname"
        
        if [ -f "$ssh_key" ]; then
            if validate_ssh_connectivity "$home_server_ip" "$home_server_ssh_port" "$ssh_user" "$ssh_key"; then
                log_info "SSH connectivity test passed"
            else
                log_warn "SSH connectivity test failed - user may not exist"
                log_info "Use --create-user to create the tunnel user automatically"
            fi
        else
            log_warn "SSH key not found - use --generate-key to create one"
        fi
        
        log_info "Test mode completed"
        exit 0
    fi
    
    # Check if already configured
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1 && 
       grep -q "^Server=127.0.0.1" "$ZBX_CONF" 2>/dev/null; then
        log_info "Zabbix agent is already configured with tunnel"
        log_info "Configuration completed successfully (idempotent)"
        exit 0
    fi
    
    # Validate SSH key exists
    if [ ! -f "$ssh_key" ]; then
        log_error "SSH key not found: $ssh_key"
        log_error "Generate it with: $0 --generate-key"
        log_error "Then create remote user with: $0 --create-user"
        exit 2
    fi
    
    # Validate SSH connectivity
    if ! validate_ssh_connectivity "$home_server_ip" "$home_server_ssh_port" "$ssh_user" "$ssh_key"; then
        log_error "SSH connectivity failed. Try creating the user with: $0 --create-user"
        exit 3
    fi
    
    # Configure Zabbix agent
    configure_zabbix_agent "$zabbix_hostname" || exit 1
    
    # Create and start tunnel service
    create_tunnel_service "$home_server_ip" "$home_server_ssh_port" "$zabbix_server_port" "$ssh_user" "$ssh_key" || exit 1
    start_tunnel_service || exit 1
    
    log_info "Zabbix agent configuration with SSH tunnel completed successfully"
}

# Execute main function with all arguments
main "$@"