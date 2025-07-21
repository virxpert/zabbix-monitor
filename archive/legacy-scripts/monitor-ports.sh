#!/bin/bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING
# ====================================================================
# This is a REFERENCE TEMPLATE demonstrating proper script structure
# DO NOT use as-is - customize configuration and logic for your needs
# Review existing scripts in /scripts/ before creating new ones
# ====================================================================
# Script: monitor-ports.sh - Port availability monitoring with alerting
# Usage: ./monitor-ports.sh [--host HOST] [--ports PORT1,PORT2] [--alert-command CMD] [--test]
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
readonly DEFAULT_HOST="localhost"
readonly DEFAULT_PORTS="22,80,443,3306,5432,10050,10051"
readonly DEFAULT_ALERT_COMMAND="/usr/bin/zabbix_sender -z zabbix-server -p 10051 -s \$(hostname) -k port.down -o"
readonly CHECK_INTERVAL=60
readonly CONNECTION_TIMEOUT=5
readonly MAX_RETRIES=3
readonly RETRY_DELAY=10
readonly STATE_FILE="/var/run/${SCRIPT_NAME}.state"

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

validate_host() {
    local host="$1"
    
    log_info "Validating host connectivity: $host"
    
    # Test basic network connectivity
    if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
        log_info "Host $host is reachable"
        return 0
    else
        log_warn "Host $host is not reachable via ping (may be expected)"
        return 0  # Don't fail on ping, ports might still be accessible
    fi
}

validate_ports() {
    local ports="$1"
    
    # Check if ports string is valid (numbers and commas only)
    if ! echo "$ports" | grep -qE '^[0-9,]+$'; then
        log_error "Invalid ports format: $ports (use comma-separated numbers)"
        return 1
    fi
    
    # Validate port ranges
    local port_array=($(echo "$ports" | tr ',' ' '))
    for port in "${port_array[@]}"; do
        if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            log_error "Invalid port number: $port (must be 1-65535)"
            return 1
        fi
    done
    
    log_info "Port validation successful: $ports"
    return 0
}

validate_alert_command() {
    local alert_cmd="$1"
    
    if [ -z "$alert_cmd" ]; then
        return 0  # Empty command is valid (no alerts)
    fi
    
    # Extract the base command (first word)
    local base_cmd=$(echo "$alert_cmd" | awk '{print $1}')
    
    if [ ! -x "$base_cmd" ]; then
        log_error "Alert command not found or not executable: $base_cmd"
        return 1
    fi
    
    log_info "Alert command validation successful: $base_cmd"
    return 0
}

check_port_connectivity() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    
    log_debug "Checking connectivity to $host:$port"
    
    # Use timeout and nc/telnet to check port
    if command -v nc >/dev/null 2>&1; then
        # Use netcat if available
        if timeout "$timeout" nc -z "$host" "$port" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v telnet >/dev/null 2>&1; then
        # Fallback to telnet
        if timeout "$timeout" telnet "$host" "$port" >/dev/null 2>&1; then
            return 0
        fi
    else
        # Fallback to bash TCP connection
        if timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1; then
            exec 3>&-  # Close the connection
            return 0
        fi
    fi
    
    return 1
}

get_previous_state() {
    local host="$1"
    local port="$2"
    
    if [ -f "$STATE_FILE" ]; then
        grep "^${host}:${port}:" "$STATE_FILE" 2>/dev/null | cut -d: -f3 || echo "unknown"
    else
        echo "unknown"
    fi
}

save_port_state() {
    local host="$1"
    local port="$2"
    local state="$3"
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Remove old state for this host:port
    grep -v "^${host}:${port}:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    
    # Add new state
    echo "${host}:${port}:${state}:$(date +%s)" >> "${STATE_FILE}.tmp"
    
    # Replace original file
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

execute_alert() {
    local alert_cmd="$1"
    local host="$2"
    local port="$3"
    local state="$4"
    local retries=0
    
    if [ -z "$alert_cmd" ]; then
        return 0  # No alert command configured
    fi
    
    log_info "Executing alert for $host:$port (state: $state)"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        # Replace placeholders in alert command
        local final_cmd="$alert_cmd"
        final_cmd=$(echo "$final_cmd" | sed "s/\$host/$host/g")
        final_cmd=$(echo "$final_cmd" | sed "s/\$port/$port/g")
        final_cmd=$(echo "$final_cmd" | sed "s/\$state/$state/g")
        
        if eval "$final_cmd \"$host:$port $state\"" >/dev/null 2>&1; then
            log_info "Alert command executed successfully"
            return 0
        fi
        
        retries=$((retries + 1))
        log_warn "Alert command failed (attempt $retries/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
    done
    
    log_error "Alert command failed after $MAX_RETRIES attempts"
    return 1
}

monitor_ports_once() {
    local host="$1"
    local ports="$2"
    local alert_cmd="$3"
    
    log_debug "Starting single port monitoring cycle"
    
    local port_array=($(echo "$ports" | tr ',' ' '))
    local total_ports=${#port_array[@]}
    local up_count=0
    local down_count=0
    local changed_count=0
    
    for port in "${port_array[@]}"; do
        local previous_state=$(get_previous_state "$host" "$port")
        local current_state
        
        if check_port_connectivity "$host" "$port" "$CONNECTION_TIMEOUT"; then
            current_state="up"
            up_count=$((up_count + 1))
            log_debug "Port $host:$port is UP"
        else
            current_state="down"
            down_count=$((down_count + 1))
            log_debug "Port $host:$port is DOWN"
        fi
        
        # Save current state
        save_port_state "$host" "$port" "$current_state"
        
        # Check for state changes
        if [ "$previous_state" != "$current_state" ] && [ "$previous_state" != "unknown" ]; then
            changed_count=$((changed_count + 1))
            log_warn "Port state changed: $host:$port $previous_state -> $current_state"
            
            # Execute alert for state changes
            if [ -n "$alert_cmd" ]; then
                execute_alert "$alert_cmd" "$host" "$port" "$current_state" || {
                    log_error "Failed to execute alert for $host:$port"
                }
            fi
        fi
    done
    
    log_info "Port scan summary: $up_count up, $down_count down, $changed_count changed (total: $total_ports)"
    return 0
}

monitor_ports_continuous() {
    local host="$1"
    local ports="$2"
    local alert_cmd="$3"
    
    log_info "Starting continuous port monitoring"
    log_info "Host: $host, Ports: $ports, Interval: ${CHECK_INTERVAL}s"
    
    while true; do
        monitor_ports_once "$host" "$ports" "$alert_cmd" || {
            log_error "Monitoring cycle failed, continuing..."
        }
        
        sleep "$CHECK_INTERVAL"
    done
}

show_port_status() {
    local host="$1"
    local ports="$2"
    
    echo "Current Port Status for $host:"
    echo "================================"
    
    local port_array=($(echo "$ports" | tr ',' ' '))
    
    for port in "${port_array[@]}"; do
        local state=$(get_previous_state "$host" "$port")
        local status_icon
        
        case "$state" in
            "up") status_icon="✓" ;;
            "down") status_icon="✗" ;;
            *) status_icon="?" ;;
        esac
        
        echo "Port $port: $status_icon $state"
    done
    
    echo ""
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Port availability monitoring with alerting

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --host HOST          Target host to monitor (default: $DEFAULT_HOST)
    --ports PORT1,PORT2  Comma-separated ports to monitor (default: $DEFAULT_PORTS)
    --alert-command CMD  Command to execute when port state changes
    --interval SECONDS   Check interval in seconds (default: $CHECK_INTERVAL)
    --timeout SECONDS    Connection timeout per port (default: $CONNECTION_TIMEOUT)
    --once               Run once instead of continuous monitoring
    --status             Show current port status and exit
    --test               Test mode - validate configuration without monitoring
    --help               Show this help message

EXAMPLES:
    $0                                                    # Use defaults
    $0 --host web-server --ports 80,443                 # Monitor web server
    $0 --host db-server --ports 3306,5432 --timeout 10  # Monitor databases
    $0 --alert-command "mail -s 'Port Alert' admin@domain.com"  # Email alerts
    $0 --once                                            # Single check
    $0 --status                                          # Show current status
    $0 --test                                            # Test mode

BOOT INTEGRATION:
    # Add to /etc/systemd/system/monitor-ports.service
    [Unit]
    Description=Port Monitor
    After=network.target
    
    [Service]
    Type=simple
    ExecStart=$PWD/$0 --host critical-server --ports 22,80,443
    Restart=always
    RestartSec=30
    
    [Install]
    WantedBy=multi-user.target

ALERT COMMAND VARIABLES:
    \$host               Replaced with target hostname
    \$port               Replaced with port number  
    \$state              Replaced with port state (up/down)

COMMON PORTS:
    22    SSH
    80    HTTP
    443   HTTPS
    3306  MySQL
    5432  PostgreSQL
    6379  Redis
    10050 Zabbix Agent
    10051 Zabbix Server

LOGS:
    All output is logged to: $LOG_FILE
    State tracking: $STATE_FILE
    Service logs: journalctl -u monitor-ports

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local host="$DEFAULT_HOST"
    local ports="$DEFAULT_PORTS"
    local alert_cmd="$DEFAULT_ALERT_COMMAND"
    local check_interval="$CHECK_INTERVAL"
    local connection_timeout="$CONNECTION_TIMEOUT"
    local run_once=false
    local show_status=false
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                host="$2"
                shift 2
                ;;
            --ports)
                ports="$2"
                shift 2
                ;;
            --alert-command)
                alert_cmd="$2"
                shift 2
                ;;
            --interval)
                check_interval="$2"
                shift 2
                ;;
            --timeout)
                connection_timeout="$2"
                shift 2
                ;;
            --once)
                run_once=true
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
    log_info "Starting port monitoring process"
    log_info "Parameters: Host=$host, Ports=$ports, Once=$run_once, Status=$show_status, Test=$test_mode"
    
    validate_root
    
    # Show status mode
    if [ "$show_status" = true ]; then
        show_port_status "$host" "$ports"
        exit 0
    fi
    
    create_lock_file
    trap cleanup EXIT
    
    # Validate configuration
    validate_host "$host" || exit 2
    validate_ports "$ports" || exit 2
    
    if [ -n "$alert_cmd" ]; then
        validate_alert_command "$alert_cmd" || {
            log_warn "Alert command validation failed, disabling alerts"
            alert_cmd=""
        }
    fi
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        log_info "Target host: $host"
        log_info "Ports to monitor: $ports"
        log_info "Alert command: ${alert_cmd:-"None configured"}"
        log_info "Check interval: $check_interval seconds"
        log_info "Connection timeout: $connection_timeout seconds"
        
        # Test a few port connections
        local port_array=($(echo "$ports" | tr ',' ' '))
        local test_ports=(${port_array[@]:0:3})  # Test first 3 ports
        
        for port in "${test_ports[@]}"; do
            if check_port_connectivity "$host" "$port" "$connection_timeout"; then
                log_info "Test connection to $host:$port - SUCCESS"
            else
                log_info "Test connection to $host:$port - FAILED"
            fi
        done
        
        log_info "Test mode completed successfully"
        exit 0
    fi
    
    # Initialize state file if not exists
    touch "$STATE_FILE"
    
    # Run monitoring
    if [ "$run_once" = true ]; then
        log_info "Running single monitoring cycle"
        monitor_ports_once "$host" "$ports" "$alert_cmd"
        log_info "Single monitoring cycle completed"
        show_port_status "$host" "$ports"
    else
        log_info "Starting continuous monitoring (interval: ${check_interval}s)"
        monitor_ports_continuous "$host" "$ports" "$alert_cmd"
    fi
}

# Execute main function with all arguments
main "$@"
