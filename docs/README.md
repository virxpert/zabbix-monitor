# Zabbix Scripts & Utilities Documentation

## Overview
This project provides comprehensive Zabbix monitoring automation with **runtime configuration injection** for Virtualizor automated server provisioning. The solution handles complete server lifecycle management with configuration values injected during provisioning.

## 🚀 Quick Start

### **Option 1: Virtualizor Recipe Automation** ⭐ **RECOMMENDED**

```bash
# 1. Download recipe with runtime configuration injection
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh

# 2. Edit configuration section with YOUR values
nano direct-download-recipe.sh

# 3. Upload to Virtualizor - automatic configuration injection during server creation!
```

### **Option 2: Manual Server Setup**

```bash
# Download and execute the master provisioning script
wget -O /tmp/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
chmod +x /tmp/virtualizor-server-setup.sh
/tmp/virtualizor-server-setup.sh
```

## 📋 Documentation Structure

### **🎯 Virtualizor Integration Guides** (Primary Focus)

| Document | Purpose | Audience |
|----------|---------|----------|
| **[Runtime Configuration Injection](runtime-configuration-injection.md)** | Complete guide to the runtime injection approach | All Users |
| **[Virtualizor Recipe Integration](virtualizor-recipe-integration.md)** | Step-by-step recipe setup and deployment | System Admins |
| **[Virtualizor Configuration Guide](virtualizor-configuration-guide.md)** | Configuration methods and security practices | DevOps Teams |

### **🔧 Technical Implementation**

| Document | Purpose | Audience |
|----------|---------|----------|
| **[Installation Guide](installation.md)** | Manual installation procedures | System Admins |
| **[Usage Guide](usage.md)** | Script usage examples and parameters | All Users |
| **[Quality Assurance](quality-assurance.md)** | Testing and validation procedures | Developers |

### **🛠️ Server Configuration**

| Document | Purpose | Audience |
|----------|---------|----------|
| **[Zabbix Server Configuration](zabbix-server-configuration.md)** | Complete server-side setup | Infrastructure Teams |
| **[SSH Tunnel Setup Guide](ssh-tunnel-setup-guide.md)** | Secure tunnel configuration | Security Teams |
| **[Administrator SSH Key Access](administrator-ssh-key-access.md)** | SSH key management procedures | System Admins |

### **🔍 Troubleshooting & Support**

| Document | Purpose | Audience |
|----------|---------|----------|
| **[Troubleshooting Guide](troubleshooting-guide.md)** | Common issues and solutions | All Users |
| **[Virtualizor Master Script](virtualizor-master-script.md)** | Advanced script configuration | Advanced Users |

## Project Structure

```
zabbix-monitor/
├── scripts/                    # Self-contained executable scripts
│   ├── install-zabbix-agent.sh # Complete Zabbix agent installation
│   ├── monitor-logs.sh         # Log file monitoring (planned)
│   ├── monitor-ports.sh        # Port availability checking (planned)
│   ├── create-secure-tunnel.sh # SSH tunnel creation (planned)
│   └── tests/                  # Test scripts for validation
├── docs/                       # Comprehensive documentation
│   ├── README.md              # This file - complete overview
│   ├── development.md         # Developer guide and patterns
│   ├── deployment.md          # Boot integration and systemd
│   └── troubleshooting-guide.md  # Common issues and solutions
├── config/                    # Configuration templates
│   ├── zabbix-install.service # Systemd service template
│   └── examples/              # Configuration examples
└── logs/                      # Auto-created log directory
```

## Key Features

### 🔧 Self-Contained Architecture
- **No Dependencies**: Each script contains all required functions and configurations
- **Single File Solutions**: One script = one complete objective
- **Embedded Configuration**: All settings contained within script headers
- **Boot-Safe Design**: Can execute during system startup without user login

### 🛡️ Reliability Features
- **Lock Files**: Prevent concurrent execution (`/var/run/[script-name].pid`)
- **Comprehensive Logging**: All actions logged with timestamps to `/var/log/zabbix-scripts/`
- **Network Retry Logic**: Exponential backoff for network operations
- **Graceful Degradation**: Continue operation when non-critical components fail
- **Atomic Operations**: Each script completes its full objective or fails cleanly

### 🔍 Debugging & Monitoring
- **Test Mode**: All scripts support `--test` flag for validation without changes
- **Detailed Logs**: Every action, error, and decision logged
- **Status Validation**: Post-execution validation of all operations
- **Exit Codes**: Standard exit codes for integration with systemd and monitoring

## Available Scripts

### install-zabbix-agent.sh
**Purpose**: Complete Zabbix agent installation and configuration

**Features**:
- Automatic OS detection (RHEL, CentOS, AlmaLinux, Rocky Linux, Ubuntu, Debian)
- Repository installation and package management
- Agent configuration with custom server/hostname
- Service startup and validation
- Network connectivity testing with retries

**Usage**:
```bash
# Basic installation
sudo ./install-zabbix-agent.sh

# Custom configuration
sudo ./install-zabbix-agent.sh --server 192.168.1.50 --hostname web01

# Test mode
sudo ./install-zabbix-agent.sh --test

# Help and examples
./install-zabbix-agent.sh --help
```

**Configuration**:
Edit the embedded configuration section at the top of the script:
```bash
readonly DEFAULT_ZABBIX_SERVER="192.168.1.100"  # Change to your server
readonly DEFAULT_HOSTNAME="$(hostname -f)"      # Or set custom hostname
readonly ZABBIX_VERSION="6.0"                   # Zabbix version
readonly MAX_RETRIES=5                           # Network retry attempts
readonly RETRY_DELAY=10                          # Base retry delay (seconds)
```

## Template Usage

### ⚠️ IMPORTANT: Template Scripts
Files in `/scripts/` marked with "TEMPLATE SCRIPT" headers are **EXAMPLES** demonstrating proper patterns. They are NOT production-ready scripts.

**Before using any template**:
1. Copy the template to a new file
2. Customize the embedded configuration section
3. Implement your specific logic and validation
4. Test thoroughly in your environment
5. Update documentation

### Template Structure
All scripts follow this embedded structure:
```bash
#!/bin/bash
# TEMPLATE SCRIPT - Customize before use
# ====================================================================
# EMBEDDED CONFIGURATION
readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly LOG_DIR="/var/log/zabbix-scripts"
# ... configuration values here

# ====================================================================
# EMBEDDED LOGGING FUNCTIONS
log_info() { log_message "INFO" "$1"; }
# ... logging functions here

# ====================================================================
# EMBEDDED UTILITY FUNCTIONS  
create_lock_file() { ... }
cleanup() { ... }
# ... utility functions here

# ====================================================================
# MAIN LOGIC
main() { ... }
main "$@"
```

## Boot Integration

### Systemd Service Creation
1. **Create service file** (`/etc/systemd/system/zabbix-install.service`):
```ini
[Unit]
Description=Install Zabbix Agent
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/path/to/scripts/install-zabbix-agent.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
```

2. **Enable and test**:
```bash
sudo systemctl daemon-reload
sudo systemctl enable zabbix-install.service
sudo systemctl start zabbix-install.service
sudo systemctl status zabbix-install.service
```

### Boot-Time Considerations
- Scripts run as root during boot
- Network may not be fully available initially
- All operations must be silent (logged, not displayed)
- Lock files prevent multiple executions
- Comprehensive error handling for unattended operation

## Logging System

### Log Location
All scripts log to `/var/log/zabbix-scripts/[script-name]-YYYYMMDD.log`

### Log Format
```
[2025-07-21 10:30:15] [INFO] [install-zabbix-agent] Starting installation process
[2025-07-21 10:30:16] [WARN] [install-zabbix-agent] Network connectivity failed (attempt 1/5)
[2025-07-21 10:30:17] [ERROR] [install-zabbix-agent] Failed to install Zabbix repository
```

### Log Levels
- **INFO**: Normal operation messages
- **WARN**: Non-critical issues that don't stop execution
- **ERROR**: Critical failures that stop execution
- **DEBUG**: Detailed troubleshooting information

### Viewing Logs
```bash
# View latest log
sudo tail -f /var/log/zabbix-scripts/install-zabbix-agent-$(date +%Y%m%d).log

# View systemd service logs
sudo journalctl -u zabbix-install.service -f

# Search for errors
sudo grep "ERROR" /var/log/zabbix-scripts/*.log
```

## Error Handling

### Exit Codes
- **0**: Success - all operations completed successfully
- **1**: General error - installation or configuration failed
- **2**: Invalid input - incorrect parameters or missing requirements
- **3**: Network timeout - unable to connect after maximum retries

### Recovery Procedures
Scripts include built-in recovery mechanisms:
- **Configuration Backup**: Original configs backed up before changes
- **Service Rollback**: Failed services restored to original state  
- **Lock File Cleanup**: Automatic cleanup on exit (success or failure)
- **Retry Logic**: Network operations retry with exponential backoff

## Testing

### Test Mode
All scripts support test mode for validation without making changes:
```bash
sudo ./scripts/install-zabbix-agent.sh --test
```

### Manual Testing Checklist
Before deploying scripts:
- [ ] Test as root without login session
- [ ] Test with network disconnected
- [ ] Test with invalid parameters
- [ ] Test concurrent execution prevention
- [ ] Verify log file creation and permissions
- [ ] Test recovery from partial failures

## Troubleshooting

### Common Issues

**Script already running**
```bash
# Check for stale lock files
sudo ls -la /var/run/*zabbix*.pid
sudo rm /var/run/install-zabbix-agent.pid  # Remove if process not running
```

**Network connectivity failures**
```bash
# Check network and DNS
ping -c 3 8.8.8.8
nslookup repo.zabbix.com

# Review retry logic in logs
sudo grep "Network connectivity" /var/log/zabbix-scripts/*.log
```

**Permission errors**
```bash
# Ensure running as root
sudo ./scripts/install-zabbix-agent.sh

# Check log directory permissions
sudo ls -la /var/log/zabbix-scripts/
sudo chown root:root /var/log/zabbix-scripts/
sudo chmod 755 /var/log/zabbix-scripts/
```

**Service startup failures**
```bash
# Check service status
sudo systemctl status zabbix-agent2
sudo journalctl -u zabbix-agent2 -n 50

# Validate configuration
sudo zabbix_agent2 -t
```

### Log Analysis
```bash
# Find all errors from today
sudo grep "$(date +%Y-%m-%d)" /var/log/zabbix-scripts/*.log | grep "ERROR"

# Monitor script execution in real-time
sudo tail -f /var/log/zabbix-scripts/*.log

# Check boot-time execution
sudo journalctl -u zabbix-install.service --since "1 hour ago"
```

## Support

### Getting Help
1. **Check Logs**: Always start with `/var/log/zabbix-scripts/`
2. **Test Mode**: Use `--test` flag to validate configuration
3. **Documentation**: Review `/docs/troubleshooting-guide.md` for common issues
4. **Service Status**: Check systemd service status and logs

### Reporting Issues
When reporting problems, include:
- Full command executed
- Complete log file contents
- Operating system and version
- Network configuration details
- Error messages and exit codes

---

**Remember**: These scripts are designed for reliability in unattended, boot-time environments. Each script is a complete, standalone solution with no dependencies on shared libraries or external configuration files.

## Recent Quality Improvements (July 2025)

### Enhanced Reliability

**Systemd Service Improvements:**

- Fixed `exit code 203/EXEC` errors through absolute path resolution
- Automatic script permission validation for service creation
- Enhanced service file generation with proper error handling

**Script Quality Enhancements:**

- Comprehensive syntax validation before execution
- Resolved unbound variable issues throughout scripts
- Centralized configuration management for consistency
- Improved error trapping and diagnostic reporting

**Production Readiness:**

- All scripts now pass enhanced syntax validation
- Systemd services start reliably across system reboots
- Better error recovery and troubleshooting support
- Documentation updated with latest improvements and solutions

These improvements ensure even greater reliability for automated deployments and system initialization scenarios.
