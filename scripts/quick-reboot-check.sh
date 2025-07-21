#!/bin/bash

# Quick Reboot Resume Diagnostic Script
# This script helps diagnose why virtualizor-server-setup.sh didn't resume after reboot

SCRIPT_NAME="virtualizor-server-setup"
STATE_FILE="/var/lib/${SCRIPT_NAME}.state"
REBOOT_FLAG_FILE="/var/lib/${SCRIPT_NAME}.reboot"
LOG_DIR="/var/log/zabbix-scripts"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d).log"

echo "QUICK REBOOT RESUME DIAGNOSTIC"
echo "=============================="
echo "Time: $(date)"
echo ""

echo "1. CHECKING FILES:"
echo "   State file: $([ -f "$STATE_FILE" ] && echo "EXISTS" || echo "MISSING") ($STATE_FILE)"
echo "   Reboot flag: $([ -f "$REBOOT_FLAG_FILE" ] && echo "EXISTS" || echo "MISSING") ($REBOOT_FLAG_FILE)"
echo "   Log file: $([ -f "$LOG_FILE" ] && echo "EXISTS" || echo "MISSING") ($LOG_FILE)"
echo ""

echo "2. SYSTEMD SERVICE STATUS:"
if systemctl is-enabled "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
    echo "   Service: ENABLED"
    if systemctl is-active "${SCRIPT_NAME}.service" >/dev/null 2>&1; then
        echo "   Status: ACTIVE"
    else
        echo "   Status: INACTIVE"
    fi
else
    echo "   Service: DISABLED"
fi
echo ""

echo "3. LAST FEW LOG ENTRIES:"
if [ -f "$LOG_FILE" ]; then
    tail -10 "$LOG_FILE" | while read line; do
        echo "   $line"
    done
else
    echo "   No log file found"
fi
echo ""

echo "4. RECOVERY OPTIONS:"
if [ -f "$STATE_FILE" ]; then
    echo "   Run: ./virtualizor-server-setup.sh --resume-after-reboot"
    echo "   Or:  ./virtualizor-server-setup.sh (will detect state automatically)"
else
    echo "   Run: ./virtualizor-server-setup.sh (fresh start)"
fi

echo ""
echo "5. DETAILED DIAGNOSTICS:"
echo "   Run: ./virtualizor-server-setup.sh --diagnose-reboot"
echo "   Or:  ./virtualizor-server-setup.sh --diagnose"

echo "=============================="
