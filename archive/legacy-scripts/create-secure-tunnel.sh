#!/bin/bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING
# ====================================================================
# This is a REFERENCE TEMPLATE demonstrating proper script structure
# DO NOT use as-is - customize configuration and logic for your needs
# Review existing scripts in /scripts/ before creating new ones
# ====================================================================
# Script: create-secure-tunnel.sh - SSH tunnel creation and management with key authentication
# Usage: ./create-secure-tunnel.sh [--remote-host HOST] [--local-port PORT] [--remote-port PORT] [--test]
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
readonly DEFAULT_REMOTE_HOST="tunnel-server.example.com"
readonly DEFAULT_REMOTE_USER="tunnel-user"
readonly DEFAULT_LOCAL_PORT="8080"
readonly DEFAULT_REMOTE_PORT="80"
readonly DEFAULT_SSH_KEY="/root/.ssh/tunnel_key"
readonly SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
readonly TUNNEL_TYPE="LOCAL"  # LOCAL or REMOTE
readonly MAX_RETRIES=5
readonly RETRY_DELAY=30
readonly HEALTH_CHECK_INTERVAL=60
readonly TUNNEL_PID_FILE="/var/run/${SCRIPT_NAME}-tunnel.pid"

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
    
    # Stop tunnel if running
    stop_tunnel
    
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

validate_ssh_key() {
    local ssh_key="$1"
    
    if [ ! -f "$ssh_key" ]; then
        log_error "SSH key file does not exist: $ssh_key"
        return 1
    fi
    
    if [ ! -r "$ssh_key" ]; then
        log_error "Cannot read SSH key file: $ssh_key (permission denied)"
        return 1
    fi
    
    # Check key format
    if ! ssh-keygen -l -f "$ssh_key" >/dev/null 2>&1; then
        log_error "Invalid SSH key format: $ssh_key"
        return 1
    fi
    
    # Set proper permissions
    chmod 600 "$ssh_key"
    log_info "SSH key validation successful: $ssh_key"
    return 0
}

validate_host_connectivity() {
    local remote_host="$1"
    local remote_user="$2"
    local ssh_key="$3"
    local retries=0
    
    log_info "Testing SSH connectivity to $remote_user@$remote_host"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if ssh -i "$ssh_key" $SSH_OPTIONS -o ConnectTimeout=10 "$remote_user@$remote_host" "echo 'Connection test successful'" >/dev/null 2>&1; then
            log_info "SSH connectivity confirmed to $remote_user@$remote_host"
            return 0
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            log_warn "SSH connectivity failed (attempt $retries/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "Failed to establish SSH connectivity after $MAX_RETRIES attempts"
    return 3
}

validate_port_available() {
    local port="$1"
    local port_type="$2"  # "local" or "remote"
    
    if [ "$port_type" = "local" ]; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "Local port $port is already in use"
            return 1
        fi
    fi
    
    # Validate port range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number: $port (must be 1-65535)"
        return 1
    fi
    
    log_info "Port validation successful: $port ($port_type)"
    return 0
}

generate_ssh_key() {
    local ssh_key="$1"
    local key_comment="tunnel-key-$(hostname)-$(date +%Y%m%d)"
    
    log_info "Generating new SSH key: $ssh_key"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$ssh_key")"
    
    # Generate key without passphrase for automation
    ssh-keygen -t rsa -b 4096 -f "$ssh_key" -N "" -C "$key_comment" >/dev/null 2>&1 || {
        log_error "Failed to generate SSH key"
        return 1
    }
    
    chmod 600 "$ssh_key"
    chmod 644 "${ssh_key}.pub"
    
    log_info "SSH key generated successfully"
    log_info "Public key: ${ssh_key}.pub"
    log_warn "IMPORTANT: Copy the public key to the remote server's authorized_keys file"
    cat "${ssh_key}.pub"
    
    return 0
}

create_tunnel() {
    local remote_host="$1"
    local remote_user="$2"
    local ssh_key="$3"
    local local_port="$4"
    local remote_port="$5"
    local tunnel_type="$6"
    
    log_info "Creating $tunnel_type tunnel: $local_port -> $remote_user@$remote_host:$remote_port"
    
    local ssh_cmd
    case "$tunnel_type" in
        "LOCAL")
            # Local port forwarding: -L local_port:localhost:remote_port
            ssh_cmd="ssh -i '$ssh_key' $SSH_OPTIONS -L $local_port:localhost:$remote_port -N -f '$remote_user@$remote_host'"
            ;;
        "REMOTE")
            # Remote port forwarding: -R remote_port:localhost:local_port
            ssh_cmd="ssh -i '$ssh_key' $SSH_OPTIONS -R $remote_port:localhost:$local_port -N -f '$remote_user@$remote_host'"
            ;;
        *)
            log_error "Invalid tunnel type: $tunnel_type (must be LOCAL or REMOTE)"
            return 1
            ;;
    esac
    
    log_debug "SSH command: $ssh_cmd"
    
    # Execute SSH tunnel command
    if eval "$ssh_cmd" 2>/dev/null; then
        # Find and save the tunnel PID
        sleep 2  # Wait for SSH to fully establish
        local tunnel_pid=$(ps aux | grep "ssh.*$remote_host" | grep -v grep | awk '{print $2}' | head -1)
        
        if [ -n "$tunnel_pid" ]; then
            echo "$tunnel_pid" > "$TUNNEL_PID_FILE"
            log_info "Tunnel established successfully (PID: $tunnel_pid)"
            return 0
        else
            log_error "Tunnel creation failed - no SSH process found"
            return 1
        fi
    else
        log_error "Failed to create SSH tunnel"
        return 1
    fi
}

check_tunnel_health() {
    if [ ! -f "$TUNNEL_PID_FILE" ]; then
        log_debug "Tunnel PID file not found"
        return 1
    fi
    
    local tunnel_pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null || echo "")
    if [ -z "$tunnel_pid" ] || ! kill -0 "$tunnel_pid" 2>/dev/null; then
        log_warn "Tunnel process not running"
        rm -f "$TUNNEL_PID_FILE"
        return 1
    fi
    
    log_debug "Tunnel health check passed (PID: $tunnel_pid)"
    return 0
}

stop_tunnel() {
    if [ -f "$TUNNEL_PID_FILE" ]; then
        local tunnel_pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$tunnel_pid" ] && kill -0 "$tunnel_pid" 2>/dev/null; then
            log_info "Stopping tunnel (PID: $tunnel_pid)"
            kill "$tunnel_pid" 2>/dev/null || true
            sleep 2
            
            # Force kill if still running
            if kill -0 "$tunnel_pid" 2>/dev/null; then
                log_warn "Force killing tunnel process"
                kill -9 "$tunnel_pid" 2>/dev/null || true
            fi
        fi
        rm -f "$TUNNEL_PID_FILE"
    fi
    
    # Kill any remaining SSH tunnels to the remote host
    pkill -f "ssh.*$remote_host" 2>/dev/null || true
    log_info "Tunnel stopped"
}

test_tunnel_connectivity() {
    local local_port="$1"
    local tunnel_type="$2"
    
    if [ "$tunnel_type" = "LOCAL" ]; then
        # Test local port forwarding by connecting to local port
        if nc -z localhost "$local_port" 2>/dev/null || telnet localhost "$local_port" </dev/null >/dev/null 2>&1; then
            log_info "Tunnel connectivity test passed: localhost:$local_port"
            return 0
        else
            log_error "Tunnel connectivity test failed: localhost:$local_port"
            return 1
        fi
    else
        log_info "Remote tunnel created - connectivity test not applicable"
        return 0
    fi
}

manage_tunnel_continuous() {
    local remote_host="$1"
    local remote_user="$2"
    local ssh_key="$3"
    local local_port="$4"
    local remote_port="$5"
    local tunnel_type="$6"
    
    log_info "Starting continuous tunnel management"
    
    while true; do
        if ! check_tunnel_health; then
            log_warn "Tunnel not healthy, attempting to recreate..."
            
            # Stop any existing tunnel
            stop_tunnel
            
            # Recreate tunnel with retries
            local retries=0
            while [ $retries -lt $MAX_RETRIES ]; do
                if create_tunnel "$remote_host" "$remote_user" "$ssh_key" "$local_port" "$remote_port" "$tunnel_type"; then
                    log_info "Tunnel recreated successfully"
                    break
                fi
                
                retries=$((retries + 1))
                if [ $retries -lt $MAX_RETRIES ]; then
                    log_warn "Tunnel recreation failed (attempt $retries/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
                    sleep $RETRY_DELAY
                fi
            done
            
            if [ $retries -eq $MAX_RETRIES ]; then
                log_error "Failed to recreate tunnel after $MAX_RETRIES attempts"
                return 1
            fi
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - SSH tunnel creation and management with key authentication

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --remote-host HOST     Remote server hostname (default: $DEFAULT_REMOTE_HOST)
    --remote-user USER     Remote SSH username (default: $DEFAULT_REMOTE_USER)
    --ssh-key PATH         SSH private key path (default: $DEFAULT_SSH_KEY)
    --local-port PORT      Local port number (default: $DEFAULT_LOCAL_PORT)
    --remote-port PORT     Remote port number (default: $DEFAULT_REMOTE_PORT)
    --tunnel-type TYPE     Tunnel type: LOCAL or REMOTE (default: $TUNNEL_TYPE)
    --generate-key         Generate new SSH key and exit
    --once                 Create tunnel once instead of continuous management
    --stop                 Stop existing tunnel and exit
    --status               Show tunnel status and exit
    --test                 Test mode - validate configuration without creating tunnel
    --help                 Show this help message

TUNNEL TYPES:
    LOCAL   Forward local port to remote port (most common)
            Access remote service via localhost:local-port
    REMOTE  Forward remote port to local port
            Remote users access local service via remote-host:remote-port

EXAMPLES:
    $0                                                    # Use defaults
    $0 --remote-host server.com --local-port 8080        # Forward local 8080 to remote 80
    $0 --tunnel-type REMOTE --remote-port 9090           # Remote access to local service
    $0 --generate-key                                     # Generate new SSH key
    $0 --once                                            # Create tunnel once
    $0 --stop                                            # Stop tunnel
    $0 --status                                          # Show status
    $0 --test                                            # Test mode

BOOT INTEGRATION:
    # Add to /etc/systemd/system/secure-tunnel.service
    [Unit]
    Description=Secure SSH Tunnel
    After=network.target
    
    [Service]
    Type=simple
    ExecStart=$PWD/$0 --remote-host server.com --local-port 8080
    ExecStop=$PWD/$0 --stop
    Restart=always
    RestartSec=30
    
    [Install]
    WantedBy=multi-user.target

SETUP PROCESS:
    1. Generate SSH key: $0 --generate-key
    2. Copy public key to remote server's ~/.ssh/authorized_keys
    3. Test connectivity: $0 --test
    4. Create tunnel: $0

COMMON USE CASES:
    Database Access:    --local-port 3306 --remote-port 3306    (MySQL)
    Web Service Access: --local-port 8080 --remote-port 80      (HTTP)
    Admin Interface:    --local-port 8443 --remote-port 443     (HTTPS)
    Remote Desktop:     --tunnel-type REMOTE --remote-port 3389 (RDP)

LOGS:
    All output is logged to: $LOG_FILE
    Tunnel PID tracking: $TUNNEL_PID_FILE
    Service logs: journalctl -u secure-tunnel

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local remote_host="$DEFAULT_REMOTE_HOST"
    local remote_user="$DEFAULT_REMOTE_USER"
    local ssh_key="$DEFAULT_SSH_KEY"
    local local_port="$DEFAULT_LOCAL_PORT"
    local remote_port="$DEFAULT_REMOTE_PORT"
    local tunnel_type="$TUNNEL_TYPE"
    local generate_key=false
    local run_once=false
    local stop_tunnel_flag=false
    local show_status=false
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remote-host)
                remote_host="$2"
                shift 2
                ;;
            --remote-user)
                remote_user="$2"
                shift 2
                ;;
            --ssh-key)
                ssh_key="$2"
                shift 2
                ;;
            --local-port)
                local_port="$2"
                shift 2
                ;;
            --remote-port)
                remote_port="$2"
                shift 2
                ;;
            --tunnel-type)
                tunnel_type="$2"
                shift 2
                ;;
            --generate-key)
                generate_key=true
                shift
                ;;
            --once)
                run_once=true
                shift
                ;;
            --stop)
                stop_tunnel_flag=true
                shift
                ;;
            --status)
                show_status=true
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
    log_info "Starting secure tunnel management"
    log_info "Parameters: Host=$remote_host, User=$remote_user, LocalPort=$local_port, RemotePort=$remote_port, Type=$tunnel_type"
    
    validate_root
    
    # Generate key mode
    if [ "$generate_key" = true ]; then
        log_info "Generating new SSH key"
        generate_ssh_key "$ssh_key"
        log_info "Key generation completed. Copy the public key to the remote server."
        exit 0
    fi
    
    # Stop tunnel mode
    if [ "$stop_tunnel_flag" = true ]; then
        log_info "Stopping tunnel"
        stop_tunnel
        exit 0
    fi
    
    # Status mode
    if [ "$show_status" = true ]; then
        if check_tunnel_health; then
            local tunnel_pid=$(cat "$TUNNEL_PID_FILE")
            echo "Tunnel Status: RUNNING (PID: $tunnel_pid)"
            echo "Local Port: $local_port"
            echo "Remote: $remote_user@$remote_host:$remote_port"
            echo "Type: $tunnel_type"
        else
            echo "Tunnel Status: NOT RUNNING"
        fi
        exit 0
    fi
    
    create_lock_file
    trap cleanup EXIT
    
    # Validate configuration
    validate_ssh_key "$ssh_key" || {
        log_warn "SSH key validation failed, attempting to generate new key"
        generate_ssh_key "$ssh_key" || exit 2
        log_error "New key generated. Copy public key to remote server and retry."
        exit 2
    }
    
    validate_port_available "$local_port" "local" || exit 2
    validate_port_available "$remote_port" "remote" || exit 2
    
    validate_host_connectivity "$remote_host" "$remote_user" "$ssh_key" || exit 3
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        log_info "Remote host: $remote_user@$remote_host"
        log_info "SSH key: $ssh_key"
        log_info "Port mapping: $local_port -> $remote_port ($tunnel_type)"
        log_info "SSH connectivity: OK"
        log_info "Test mode completed successfully"
        exit 0
    fi
    
    # Create tunnel
    if [ "$run_once" = true ]; then
        log_info "Creating tunnel (run-once mode)"
        create_tunnel "$remote_host" "$remote_user" "$ssh_key" "$local_port" "$remote_port" "$tunnel_type"
        
        # Test connectivity
        sleep 3
        test_tunnel_connectivity "$local_port" "$tunnel_type" || {
            log_error "Tunnel connectivity test failed"
            exit 1
        }
        
        log_info "Tunnel created successfully (run-once mode completed)"
    else
        log_info "Starting continuous tunnel management"
        manage_tunnel_continuous "$remote_host" "$remote_user" "$ssh_key" "$local_port" "$remote_port" "$tunnel_type"
    fi
}

# Execute main function with all arguments
main "$@"
