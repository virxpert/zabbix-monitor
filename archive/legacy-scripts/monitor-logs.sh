#!/bin/bash
# ====================================================================
# TEMPLATE SCRIPT - READ BEFORE USING
# ====================================================================
# This is a REFERENCE TEMPLATE demonstrating proper script structure
# DO NOT use as-is - customize configuration and logic for your needs
# Review existing scripts in /scripts/ before creating new ones
# ====================================================================
# Script: monitor-logs.sh - Log file monitoring with pattern detection and alerting
# Usage: ./monitor-logs.sh [--logfile PATH] [--pattern TEXT] [--alert-command CMD] [--test]
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
readonly DEFAULT_LOGFILE="/var/log/messages"
readonly DEFAULT_PATTERN="ERROR|CRITICAL|FATAL"
readonly DEFAULT_ALERT_COMMAND="/usr/bin/zabbix_sender -z zabbix-server -p 10051 -s \$(hostname) -k log.errors -o"
readonly CHECK_INTERVAL=30
readonly MAX_LINES_PER_CHECK=1000
readonly POSITION_FILE="/var/run/${SCRIPT_NAME}.pos"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

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

validate_logfile() {
    local logfile="$1"
    
    if [ ! -f "$logfile" ]; then
        log_error "Log file does not exist: $logfile"
        return 1
    fi
    
    if [ ! -r "$logfile" ]; then
        log_error "Cannot read log file: $logfile (permission denied)"
        return 1
    fi
    
    log_info "Log file validation successful: $logfile"
    return 0
}

validate_alert_command() {
    local alert_cmd="$1"
    
    # Extract the base command (first word)
    local base_cmd=$(echo "$alert_cmd" | awk '{print $1}')
    
    if [ ! -x "$base_cmd" ]; then
        log_error "Alert command not found or not executable: $base_cmd"
        return 1
    fi
    
    log_info "Alert command validation successful: $base_cmd"
    return 0
}

get_file_position() {
    local logfile="$1"
    
    if [ -f "$POSITION_FILE" ]; then
        local saved_pos=$(cat "$POSITION_FILE" 2>/dev/null || echo "0")
        local current_size=$(stat -c %s "$logfile" 2>/dev/null || echo "0")
        
        # If file was rotated (size smaller than saved position), start from beginning
        if [ "$current_size" -lt "$saved_pos" ]; then
            log_warn "Log file appears to have been rotated, starting from beginning"
            echo "0"
        else
            echo "$saved_pos"
        fi
    else
        # First run - start from current end of file
        stat -c %s "$logfile" 2>/dev/null || echo "0"
    fi
}

save_file_position() {
    local position="$1"
    echo "$position" > "$POSITION_FILE" 2>/dev/null || {
        log_error "Failed to save file position"
        return 1
    }
}

read_new_lines() {
    local logfile="$1"
    local start_pos="$2"
    local max_lines="$3"
    
    # Use tail with byte offset to read from specific position
    tail -c +$((start_pos + 1)) "$logfile" 2>/dev/null | head -n "$max_lines"
}

search_patterns() {
    local pattern="$1"
    local input_data="$2"
    
    # Use grep to find matching patterns, return count and sample lines
    local matches=$(echo "$input_data" | grep -E "$pattern" 2>/dev/null || true)
    local match_count=$(echo "$matches" | grep -c . 2>/dev/null || echo "0")
    
    if [ "$match_count" -gt 0 ]; then
        log_info "Found $match_count pattern matches"
        echo "$matches"
        return 0
    else
        return 1
    fi
}

execute_alert() {
    local alert_cmd="$1"
    local match_count="$2"
    local sample_matches="$3"
    local retries=0
    
    log_info "Executing alert command for $match_count matches"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        # Replace placeholder with actual match count
        local final_cmd=$(echo "$alert_cmd" | sed "s/\$match_count/$match_count/g")
        
        if eval "$final_cmd \"$match_count\"" >/dev/null 2>&1; then
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

monitor_logfile_once() {
    local logfile="$1"
    local pattern="$2"
    local alert_cmd="$3"
    
    log_debug "Starting single monitoring cycle"
    
    # Get current file position
    local start_pos=$(get_file_position "$logfile")
    local current_size=$(stat -c %s "$logfile" 2>/dev/null || echo "0")
    
    if [ "$current_size" -le "$start_pos" ]; then
        log_debug "No new data in log file"
        return 0
    fi
    
    # Read new lines from log file
    local new_data=$(read_new_lines "$logfile" "$start_pos" "$MAX_LINES_PER_CHECK")
    local new_pos=$(stat -c %s "$logfile")
    
    if [ -z "$new_data" ]; then
        log_debug "No new data read from log file"
        save_file_position "$new_pos"
        return 0
    fi
    
    log_debug "Read $((new_pos - start_pos)) bytes of new data"
    
    # Search for patterns in new data
    if search_matches=$(search_patterns "$pattern" "$new_data"); then
        local match_count=$(echo "$search_matches" | wc -l)
        log_warn "Found $match_count matching patterns in log"
        
        # Execute alert command
        if [ -n "$alert_cmd" ]; then
            execute_alert "$alert_cmd" "$match_count" "$search_matches" || {
                log_error "Failed to execute alert command"
            }
        fi
        
        # Log sample matches for debugging
        log_info "Sample matches: $(echo "$search_matches" | head -3 | tr '\n' '; ')"
    else
        log_debug "No pattern matches found in new data"
    fi
    
    # Save new position
    save_file_position "$new_pos"
    return 0
}

monitor_logfile_continuous() {
    local logfile="$1"
    local pattern="$2"
    local alert_cmd="$3"
    
    log_info "Starting continuous log monitoring"
    log_info "Logfile: $logfile, Pattern: $pattern, Interval: ${CHECK_INTERVAL}s"
    
    while true; do
        monitor_logfile_once "$logfile" "$pattern" "$alert_cmd" || {
            log_error "Monitoring cycle failed, continuing..."
        }
        
        sleep "$CHECK_INTERVAL"
    done
}

# ====================================================================
# EMBEDDED HELP AND USAGE
# ====================================================================
show_help() {
    cat << EOF
$SCRIPT_NAME - Log file monitoring with pattern detection and alerting

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --logfile PATH       Log file to monitor (default: $DEFAULT_LOGFILE)
    --pattern REGEX      Pattern to search for (default: $DEFAULT_PATTERN)
    --alert-command CMD  Command to execute when pattern found
    --interval SECONDS   Check interval in seconds (default: $CHECK_INTERVAL)
    --once               Run once instead of continuous monitoring
    --test               Test mode - validate configuration without monitoring
    --help               Show this help message

EXAMPLES:
    $0                                                    # Use defaults
    $0 --logfile /var/log/httpd/error.log                # Monitor Apache errors
    $0 --pattern "FATAL|PANIC" --interval 10             # Custom pattern and interval
    $0 --alert-command "mail -s Alert admin@domain.com"  # Custom alert
    $0 --once                                            # Single check
    $0 --test                                            # Test mode

BOOT INTEGRATION:
    # Add to /etc/systemd/system/monitor-logs.service
    [Unit]
    Description=Log File Monitor
    After=network.target
    
    [Service]
    Type=simple
    ExecStart=$PWD/$0
    Restart=always
    RestartSec=30
    
    [Install]
    WantedBy=multi-user.target

PATTERN EXAMPLES:
    ERROR|CRITICAL|FATAL           # Multiple severity levels
    "Out of memory"                # Specific error message
    "user.*failed.*login"          # Failed login attempts
    "HTTP.*[45][0-9][0-9]"        # HTTP 4xx/5xx errors

LOGS:
    All output is logged to: $LOG_FILE
    Position tracking: $POSITION_FILE
    Service logs: journalctl -u monitor-logs

EOF
}

# ====================================================================
# MAIN EXECUTION LOGIC
# ====================================================================
main() {
    local logfile="$DEFAULT_LOGFILE"
    local pattern="$DEFAULT_PATTERN"
    local alert_cmd="$DEFAULT_ALERT_COMMAND"
    local check_interval="$CHECK_INTERVAL"
    local run_once=false
    local test_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --logfile)
                logfile="$2"
                shift 2
                ;;
            --pattern)
                pattern="$2"
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
            --once)
                run_once=true
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
    log_info "Starting log monitoring process"
    log_info "Parameters: Logfile=$logfile, Pattern=$pattern, Once=$run_once, Test=$test_mode"
    
    validate_root
    create_lock_file
    trap cleanup EXIT
    
    # Validate configuration
    validate_logfile "$logfile" || exit 2
    
    if [ -n "$alert_cmd" ]; then
        validate_alert_command "$alert_cmd" || {
            log_warn "Alert command validation failed, disabling alerts"
            alert_cmd=""
        }
    fi
    
    # Test mode - validate configuration only
    if [ "$test_mode" = true ]; then
        log_info "Running in test mode - validation only"
        log_info "Log file: $logfile ($(stat -c %s "$logfile") bytes)"
        log_info "Pattern: $pattern"
        log_info "Alert command: ${alert_cmd:-"None configured"}"
        log_info "Check interval: ${check_interval} seconds"
        log_info "Test mode completed successfully"
        exit 0
    fi
    
    # Initialize position file if not exists
    if [ ! -f "$POSITION_FILE" ]; then
        get_file_position "$logfile" > "$POSITION_FILE"
        log_info "Initialized position file: $POSITION_FILE"
    fi
    
    # Run monitoring
    if [ "$run_once" = true ]; then
        log_info "Running single monitoring cycle"
        monitor_logfile_once "$logfile" "$pattern" "$alert_cmd"
        log_info "Single monitoring cycle completed"
    else
        log_info "Starting continuous monitoring (interval: ${check_interval}s)"
        monitor_logfile_continuous "$logfile" "$pattern" "$alert_cmd"
    fi
}

# Execute main function with all arguments
main "$@"
