# Troubleshooting Exit Code 1 Error

## Error Analysis

**Error Message:** `[2025-07-21 13:36:21] [ERROR] [virtualizor-server-setup] Script failed with exit code 1`

**Exit Code 1 Meaning:** General error condition - the script encountered a problem during execution.

## Enhanced Diagnostics Added ✅

### 1. **Improved Error Reporting**
The script now provides detailed failure information including:
- System information (OS, kernel, uptime)
- Network connectivity status
- Disk space and memory usage
- Current stage and state information
- Specific troubleshooting steps

### 2. **New Diagnostic Commands**
```bash
# Comprehensive system diagnostics
./virtualizor-server-setup.sh --diagnose

# Quick status check
./virtualizor-server-setup.sh --quick-status

# Full system validation
./virtualizor-server-setup.sh --validate
```

## Common Exit Code 1 Causes

### **1. Root Privileges Issue**
```bash
# Check if running as root
sudo ./virtualizor-server-setup.sh
```

### **2. Network Connectivity Problems**
```bash
# Test network connectivity
ping -c 3 8.8.8.8
ping -c 3 1.1.1.1

# Check DNS resolution
nslookup google.com
```

### **3. Disk Space Issues**
```bash
# Check available disk space
df -h
# Ensure at least 1GB free space for updates and packages
```

### **4. OS Detection Failure**
```bash
# Verify OS release file exists
cat /etc/os-release

# Check supported OS
# Supported: Ubuntu, Debian, RHEL, CentOS, AlmaLinux, Rocky
```

### **5. Package Repository Problems**
```bash
# For Debian/Ubuntu
apt-get update

# For RHEL/CentOS
yum update
# or
dnf update
```

### **6. Lock File Conflicts**
```bash
# Check for existing lock file
ls -la /var/run/virtualizor-server-setup.pid

# Clean up if needed
./virtualizor-server-setup.sh --cleanup
```

## Troubleshooting Steps

### **Step 1: Run Diagnostics**
```bash
./virtualizor-server-setup.sh --diagnose
```

This will show:
- System information
- Network status
- Disk space
- Memory usage
- Service status
- Script state
- Recent log entries

### **Step 2: Check Detailed Logs**
```bash
# View the full log file
tail -50 /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Check system logs
journalctl -xe
```

### **Step 3: Test Individual Components**
```bash
# Test network connectivity
curl -I https://repo.zabbix.com

# Test package manager
apt-get update  # Ubuntu/Debian
yum check-update  # RHEL/CentOS

# Check systemd
systemctl status
```

### **Step 4: Manual Stage Execution**
If the script fails, you can resume from specific stages:
```bash
# Clean start
./virtualizor-server-setup.sh --cleanup

# Start from specific stage
./virtualizor-server-setup.sh --stage init
./virtualizor-server-setup.sh --stage updates
./virtualizor-server-setup.sh --stage zabbix-install
```

## Recovery Commands

### **Clean Recovery**
```bash
# Complete cleanup and fresh start
./virtualizor-server-setup.sh --cleanup
./virtualizor-server-setup.sh
```

### **State Recovery**
```bash
# Check current state
./virtualizor-server-setup.sh --status

# Continue from saved state
./virtualizor-server-setup.sh
```

## Expected Resolution

With the enhanced error reporting, the next failure will provide:

1. **Detailed error context** - exactly what failed and why
2. **System diagnostics** - network, disk, memory status
3. **Specific troubleshooting steps** - tailored to the failure type
4. **Recovery options** - how to fix and continue

## Next Steps

1. **Run the enhanced script** - it will now provide much more detailed error information
2. **Use diagnostic tools** - `--diagnose` option gives comprehensive system info
3. **Check specific failure points** - enhanced logging shows exactly where it fails
4. **Follow targeted solutions** - error messages now include specific fix instructions

The script is now much more robust and will provide the detailed information needed to identify and resolve the specific cause of exit code 1.
