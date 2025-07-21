#!/bin/bash
# Script: virtualizor-recipe-diagnostic.sh - Diagnose Virtualizor recipe execution issues (Multi-OS)
# Usage: ./virtualizor-recipe-diagnostic.sh
# Compatible with: Ubuntu 18.04-24.04, Debian 10-12, RHEL/CentOS 7-9, AlmaLinux/Rocky 8-9
# Author: System Administrator | Date: 2025-07-21

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_FILE="/var/log/${SCRIPT_NAME}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case "$level" in
        "ERROR"|"FAIL") color="$RED" ;;
        "SUCCESS"|"PASS") color="$GREEN" ;;
        "WARNING"|"WARN") color="$YELLOW" ;;
        "INFO") color="$BLUE" ;;
        *) color="$NC" ;;
    esac
    
    printf "${color}[%s] [%s] %s${NC}\n" "$timestamp" "$level" "$message" | tee -a "$LOG_FILE"
}

# Enhanced OS detection
detect_os_detailed() {
    log_message "INFO" "=== Operating System Detection ==="
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_message "SUCCESS" "OS Detected: $PRETTY_NAME"
        log_message "INFO" "Distribution ID: $ID"
        log_message "INFO" "Version ID: ${VERSION_ID:-'Not specified'}"
        log_message "INFO" "Version Codename: ${VERSION_CODENAME:-'Not specified'}"
        
        # OS-specific information
        case "$ID" in
            ubuntu)
                if command -v lsb_release >/dev/null 2>&1; then
                    log_message "INFO" "Ubuntu-specific: $(lsb_release -d | cut -f2)"
                else
                    log_message "INFO" "Ubuntu-specific: lsb_release not available"
                fi
                ;;
            debian)
                if [ -f /etc/debian_version ]; then
                    log_message "INFO" "Debian version: $(cat /etc/debian_version)"
                fi
                ;;
            rhel|centos|almalinux|rocky|fedora)
                if [ -f /etc/redhat-release ]; then
                    log_message "INFO" "Red Hat family: $(cat /etc/redhat-release)"
                fi
                ;;
            opensuse*|sles)
                log_message "INFO" "SUSE family detected"
                ;;
            alpine)
                log_message "INFO" "Alpine Linux detected"
                ;;
        esac
    else
        log_message "WARNING" "/etc/os-release not found"
        log_message "INFO" "Fallback OS info: $(uname -a)"
    fi
    
    log_message "INFO" "Kernel: $(uname -r)"
    log_message "INFO" "Architecture: $(uname -m)"
    log_message "INFO" "Hostname: $(hostname)"
    echo ""
}

# Check functions
check_passed() {
    echo -e "${GREEN}✅ $1${NC}"
    log_message "PASS" "$1"
}

check_failed() {
    echo -e "${RED}❌ $1${NC}"
    log_message "FAIL" "$1"
}

check_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log_message "WARN" "$1"
}

# Enhanced package manager detection
detect_package_manager() {
    log_message "INFO" "=== Package Manager Detection ==="
    
    if command -v apt-get >/dev/null 2>&1; then
        check_passed "APT package manager available"
        log_message "INFO" "APT version: $(apt-get --version 2>/dev/null | head -1 || echo 'Version unavailable')"
        return 0
    elif command -v dnf >/dev/null 2>&1; then
        check_passed "DNF package manager available"
        log_message "INFO" "DNF version: $(dnf --version 2>/dev/null | head -1 || echo 'Version unavailable')"
        return 0
    elif command -v yum >/dev/null 2>&1; then
        check_passed "YUM package manager available"
        log_message "INFO" "YUM version: $(yum --version 2>/dev/null | head -1 || echo 'Version unavailable')"
        return 0
    elif command -v zypper >/dev/null 2>&1; then
        check_passed "Zypper package manager available"
        log_message "INFO" "Zypper version: $(zypper --version 2>/dev/null || echo 'Version unavailable')"
        return 0
    elif command -v apk >/dev/null 2>&1; then
        check_passed "APK package manager available (Alpine)"
        log_message "INFO" "APK version: $(apk --version 2>/dev/null || echo 'Version unavailable')"
        return 0
    else
        check_failed "No supported package manager found"
        return 1
    fi
}

# Enhanced network tools check
check_network_tools() {
    log_message "INFO" "=== Network Tools Check ==="
    
    # Check wget
    if command -v wget >/dev/null 2>&1; then
        check_passed "wget is available"
        log_message "INFO" "wget version: $(wget --version 2>/dev/null | head -1 || echo 'Version unavailable')"
    else
        check_warning "wget not found - may need installation"
    fi
    
    # Check curl
    if command -v curl >/dev/null 2>&1; then
        check_passed "curl is available"
        log_message "INFO" "curl version: $(curl --version 2>/dev/null | head -1 || echo 'Version unavailable')"
    else
        check_warning "curl not found"
    fi
    
    # Check ping
    if command -v ping >/dev/null 2>&1; then
        check_passed "ping is available"
    else
        check_failed "ping not available"
    fi
    
    echo ""
}

check_failed() {
    echo -e "${RED}❌ $1${NC}"
    log_message "FAIL" "$1"
}

check_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log_message "WARN" "$1"
}

check_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log_message "INFO" "$1"
}

echo -e "${BLUE}🔍 Virtualizor Recipe Diagnostic Tool${NC}"
echo "================================================="

# Check if we're running as root
if [ "$EUID" -eq 0 ]; then
    check_passed "Running as root"
else
    check_failed "Not running as root - some checks may fail"
fi

echo -e "\n${BLUE}📋 System Information${NC}"
echo "------------------------"
check_info "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
check_info "Kernel: $(uname -r)"
check_info "Uptime: $(uptime -p)"
check_info "Current time: $(date)"

echo -e "\n${BLUE}🌐 Network Connectivity${NC}"
echo "-----------------------------"
if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    check_passed "Internet connectivity (8.8.8.8)"
else
    check_failed "Internet connectivity failed"
fi

if nslookup github.com >/dev/null 2>&1; then
    check_passed "DNS resolution (github.com)"
else
    check_failed "DNS resolution failed"
fi

if wget --timeout=10 --spider "https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh" >/dev/null 2>&1; then
    check_passed "GitHub script access"
else
    check_failed "Cannot access GitHub script URL"
fi

echo -e "\n${BLUE}📁 Virtualizor Recipe Evidence${NC}"
echo "------------------------------------"

# Check for recipe logs
recipe_logs=$(find /root -name "recipe_*.log" 2>/dev/null | head -10)
if [ -n "$recipe_logs" ]; then
    check_passed "Recipe logs found:"
    echo "$recipe_logs" | while read -r log_file; do
        if [ -s "$log_file" ]; then
            check_info "  📄 $log_file ($(wc -l < "$log_file") lines)"
        else
            check_warning "  📄 $log_file (empty)"
        fi
    done
else
    check_warning "No recipe logs found in /root/"
fi

# Check for exec_recipe files
if ls /root/exec_recipe.* >/dev/null 2>&1; then
    check_info "Found exec_recipe files:"
    ls -la /root/exec_recipe.* | while read -r line; do
        check_info "  $line"
    done
else
    check_warning "No exec_recipe files found"
fi

# Check rc.local
if [ -f /etc/rc.local ]; then
    check_passed "rc.local exists"
    if [ -s /etc/rc.local ]; then
        check_info "rc.local content preview:"
        head -n 10 /etc/rc.local | sed 's/^/    /'
    else
        check_warning "rc.local is empty"
    fi
else
    check_warning "rc.local does not exist"
fi

echo -e "\n${BLUE}🛠️  Setup Script Status${NC}"
echo "----------------------------"

# Check if script exists
if [ -f "/root/virtualizor-server-setup.sh" ]; then
    check_passed "virtualizor-server-setup.sh found in /root/"
    if [ -x "/root/virtualizor-server-setup.sh" ]; then
        check_passed "Script is executable"
    else
        check_failed "Script is not executable"
    fi
    
    # Check syntax
    if bash -n "/root/virtualizor-server-setup.sh" 2>/dev/null; then
        check_passed "Script syntax is valid"
    else
        check_failed "Script has syntax errors"
    fi
else
    check_failed "virtualizor-server-setup.sh not found in /root/"
fi

# Check for script in other locations
other_locations=$(find /tmp /usr/local/bin -name "*virtualizor-server-setup*" 2>/dev/null | head -5)
if [ -n "$other_locations" ]; then
    check_info "Script found in other locations:"
    echo "$other_locations" | while read -r location; do
        check_info "  📄 $location"
    done
fi

echo -e "\n${BLUE}📊 Service Status${NC}"
echo "---------------------"

# Check for running processes
if pgrep -f "virtualizor-server-setup" >/dev/null; then
    check_passed "virtualizor-server-setup process is running"
    check_info "Process details:"
    ps aux | grep "virtualizor-server-setup" | grep -v grep | sed 's/^/    /'
else
    check_info "No virtualizor-server-setup process currently running"
fi

# Check for systemd service
if systemctl list-unit-files | grep -q "virtualizor-server-setup"; then
    check_passed "virtualizor-server-setup.service exists"
    service_status=$(systemctl is-active virtualizor-server-setup 2>/dev/null || echo "inactive")
    check_info "Service status: $service_status"
else
    check_info "No virtualizor-server-setup systemd service found"
fi

echo -e "\n${BLUE}📝 Log Files${NC}"
echo "---------------"

# Check for setup logs
setup_logs=$(find /var/log -name "*virtualizor-server-setup*" 2>/dev/null | head -10)
if [ -n "$setup_logs" ]; then
    check_passed "Setup logs found:"
    echo "$setup_logs" | while read -r log_file; do
        if [ -s "$log_file" ]; then
            check_info "  📄 $log_file ($(wc -l < "$log_file") lines)"
        else
            check_warning "  📄 $log_file (empty)"
        fi
    done
else
    check_warning "No setup logs found in /var/log/"
fi

# Check for zabbix logs
if [ -d "/var/log/zabbix-scripts" ]; then
    check_passed "Zabbix scripts log directory exists"
    zabbix_logs=$(find /var/log/zabbix-scripts -name "*.log" 2>/dev/null | head -5)
    if [ -n "$zabbix_logs" ]; then
        echo "$zabbix_logs" | while read -r log_file; do
            check_info "  📄 $log_file ($(wc -l < "$log_file") lines)"
        done
    else
        check_warning "No log files in /var/log/zabbix-scripts/"
    fi
else
    check_info "Zabbix scripts log directory does not exist yet"
fi

echo -e "\n${BLUE}🔍 System Boot Analysis${NC}"
echo "----------------------------"

# Check boot logs for recipe execution
recipe_boot_logs=$(journalctl -b 0 --no-pager 2>/dev/null | grep -i "recipe\|virtualizor\|exec_recipe" | head -10)
if [ -n "$recipe_boot_logs" ]; then
    check_passed "Found recipe-related boot logs:"
    echo "$recipe_boot_logs" | sed 's/^/    /'
else
    check_warning "No recipe-related entries in boot logs"
fi

# Check for recent errors
recent_errors=$(journalctl -b 0 --no-pager -p err 2>/dev/null | tail -10)
if [ -n "$recent_errors" ]; then
    check_warning "Recent system errors found:"
    echo "$recent_errors" | sed 's/^/    /'
else
    check_passed "No recent system errors found"
fi

echo -e "\n${BLUE}🔧 Recommendations${NC}"
echo "----------------------"

# Generate recommendations based on findings
if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${RED}🔴 CRITICAL: Fix network connectivity first${NC}"
fi

if [ ! -f "/root/virtualizor-server-setup.sh" ]; then
    echo -e "${YELLOW}🟡 RECOMMENDED: Download the setup script manually:${NC}"
    echo "   wget -O /root/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"
    echo "   chmod +x /root/virtualizor-server-setup.sh"
fi

if [ -n "$recipe_logs" ]; then
    echo -e "${BLUE}🔵 INFO: Review recipe logs for errors:${NC}"
    echo "$recipe_logs" | while read -r log_file; do
        echo "   cat $log_file"
    done
fi

echo -e "\n${GREEN}✅ Diagnostic completed. Log saved to: $LOG_FILE${NC}"
echo "================================================="
