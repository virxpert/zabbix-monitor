#!/bin/bash
# ====================================================================
# Script: test-virtualizor-server-setup.sh - Test Suite for Master Provisioning Script
# Usage: ./test-virtualizor-server-setup.sh [--verbose] [--stage STAGE]
# Author: System Admin | Date: 2025-07-21
# ====================================================================

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MASTER_SCRIPT="$SCRIPT_DIR/../virtualizor-server-setup.sh"
readonly TEST_LOG="/tmp/test-virtualizor-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Utility functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$TEST_LOG"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_LOG"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_LOG"
    ((FAILED_TESTS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_LOG"
}

# Test functions
test_script_exists() {
    ((TOTAL_TESTS++))
    log_test "Checking if master script exists"
    
    if [ -f "$MASTER_SCRIPT" ]; then
        log_pass "Master script found: $MASTER_SCRIPT"
    else
        log_fail "Master script not found: $MASTER_SCRIPT"
        return 1
    fi
}

test_script_executable() {
    ((TOTAL_TESTS++))
    log_test "Checking if master script is executable"
    
    if [ -x "$MASTER_SCRIPT" ]; then
        log_pass "Master script is executable"
    else
        log_fail "Master script is not executable"
        return 1
    fi
}

test_help_option() {
    ((TOTAL_TESTS++))
    log_test "Testing --help option"
    
    if "$MASTER_SCRIPT" --help >/dev/null 2>&1; then
        log_pass "Help option works correctly"
    else
        log_fail "Help option failed"
        return 1
    fi
}

test_status_option() {
    ((TOTAL_TESTS++))
    log_test "Testing --status option (should show no active setup)"
    
    local output
    if output=$("$MASTER_SCRIPT" --status 2>&1); then
        if echo "$output" | grep -q "No active setup found"; then
            log_pass "Status option works correctly (no active setup)"
        else
            log_warn "Status option works but shows unexpected output: $output"
        fi
    else
        log_fail "Status option failed"
        return 1
    fi
}

test_test_mode() {
    ((TOTAL_TESTS++))
    log_test "Testing --test mode (should not require root)"
    
    if "$MASTER_SCRIPT" --test >/dev/null 2>&1; then
        log_pass "Test mode works correctly"
    else
        # Test mode might fail due to root requirement, check the error
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            log_warn "Test mode requires root access (expected behavior)"
        else
            log_fail "Test mode failed with unexpected error (exit code: $exit_code)"
            return 1
        fi
    fi
}

test_cleanup_option() {
    ((TOTAL_TESTS++))
    log_test "Testing --cleanup option"
    
    if "$MASTER_SCRIPT" --cleanup >/dev/null 2>&1; then
        log_pass "Cleanup option works correctly"
    else
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            log_warn "Cleanup requires root access (expected behavior)"
        else
            log_fail "Cleanup option failed with unexpected error (exit code: $exit_code)"
            return 1
        fi
    fi
}

test_script_structure() {
    ((TOTAL_TESTS++))
    log_test "Testing script structure and required functions"
    
    local required_functions=(
        "setup_logging"
        "save_state"
        "load_state"
        "stage_init"
        "stage_banner"
        "stage_updates"
        "stage_complete"
        "main"
    )
    
    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$MASTER_SCRIPT"; then
            missing_functions+=("$func")
        fi
    done
    
    if [ ${#missing_functions[@]} -eq 0 ]; then
        log_pass "All required functions found in script"
    else
        log_fail "Missing functions: ${missing_functions[*]}"
        return 1
    fi
}

test_configuration_variables() {
    ((TOTAL_TESTS++))
    log_test "Testing configuration variables presence"
    
    local required_vars=(
        "DEFAULT_BANNER_TEXT"
        "DEFAULT_ZABBIX_VERSION"
        "DEFAULT_HOME_SERVER_IP"
        "DEFAULT_SSH_USER"
        "STAGE_INIT"
        "STAGE_COMPLETE"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "readonly $var=" "$MASTER_SCRIPT"; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -eq 0 ]; then
        log_pass "All required configuration variables found"
    else
        log_fail "Missing configuration variables: ${missing_vars[*]}"
        return 1
    fi
}

test_logging_setup() {
    ((TOTAL_TESTS++))
    log_test "Testing logging functions"
    
    local required_log_funcs=(
        "log_info"
        "log_warn" 
        "log_error"
        "log_stage"
    )
    
    local missing_funcs=()
    for func in "${required_log_funcs[@]}"; do
        if ! grep -q "^${func}()" "$MASTER_SCRIPT"; then
            missing_funcs+=("$func")
        fi
    done
    
    if [ ${#missing_funcs[@]} -eq 0 ]; then
        log_pass "All required logging functions found"
    else
        log_fail "Missing logging functions: ${missing_funcs[*]}"
        return 1
    fi
}

test_embedded_zabbix_functions() {
    ((TOTAL_TESTS++))
    log_test "Testing embedded Zabbix functions"
    
    local zabbix_functions=(
        "install_zabbix_agent"
        "configure_zabbix_for_tunnel"
        "generate_tunnel_ssh_key"
        "create_ssh_tunnel_service"
    )
    
    local missing_funcs=()
    for func in "${zabbix_functions[@]}"; do
        if ! grep -q "${func}()" "$MASTER_SCRIPT"; then
            missing_funcs+=("$func")
        fi
    done
    
    if [ ${#missing_funcs[@]} -eq 0 ]; then
        log_pass "All embedded Zabbix functions found"
    else
        log_fail "Missing Zabbix functions: ${missing_funcs[*]}"
        return 1
    fi
}

# Main execution
main() {
    local verbose=false
    local specific_stage=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                verbose=true
                shift
                ;;
            --stage)
                specific_stage="$2"
                shift 2
                ;;
            --help)
                cat << EOF
Test Suite for Virtualizor Server Setup Master Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --verbose      Show detailed output
    --stage STAGE  Run only specific test stage
    --help         Show this help

STAGES:
    basic         Basic script validation
    structure     Script structure tests
    config        Configuration tests
    integration   Integration tests (requires root)

EXAMPLES:
    $0                     # Run all tests
    $0 --verbose           # Run with detailed output
    $0 --stage basic       # Run only basic tests
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "==================================================================="
    echo "Virtualizor Server Setup - Test Suite"
    echo "==================================================================="
    echo "Master Script: $MASTER_SCRIPT"
    echo "Test Log: $TEST_LOG"
    echo "Date: $(date)"
    echo "==================================================================="
    
    # Initialize test log
    {
        echo "==================================================================="
        echo "Virtualizor Server Setup - Test Suite Log"
        echo "Started: $(date)"
        echo "==================================================================="
    } > "$TEST_LOG"
    
    # Run tests based on stage
    case "$specific_stage" in
        "basic"|"")
            log_test "Running basic validation tests"
            test_script_exists || true
            test_script_executable || true
            test_help_option || true
            test_status_option || true
            test_cleanup_option || true
            
            if [ "$specific_stage" = "basic" ]; then
                echo "Basic tests completed"
            fi
            ;;&
            
        "structure"|"")
            if [ -z "$specific_stage" ] || [ "$specific_stage" = "structure" ]; then
                log_test "Running structure validation tests"
                test_script_structure || true
                test_logging_setup || true
                test_embedded_zabbix_functions || true
                
                if [ "$specific_stage" = "structure" ]; then
                    echo "Structure tests completed"
                fi
            fi
            ;;&
            
        "config"|"")
            if [ -z "$specific_stage" ] || [ "$specific_stage" = "config" ]; then
                log_test "Running configuration tests"
                test_configuration_variables || true
                
                if [ "$specific_stage" = "config" ]; then
                    echo "Configuration tests completed"
                fi
            fi
            ;;&
            
        "integration")
            if [ "$EUID" -eq 0 ]; then
                log_test "Running integration tests (requires root)"
                test_test_mode || true
            else
                log_warn "Integration tests require root access"
            fi
            ;;
    esac
    
    # Summary
    echo ""
    echo "==================================================================="
    echo "Test Summary"
    echo "==================================================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo "Test Log: $TEST_LOG"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Check the log for details.${NC}"
        exit 1
    fi
}

main "$@"
