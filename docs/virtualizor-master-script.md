# Virtualizor Server Setup - Master Script Documentation

## Overview

`virtualizor-server-setup.sh` is a comprehensive master script designed specifically for **Virtualizor software recipe execution**. It handles the complete Linux server provisioning lifecycle from initial boot through Zabbix agent setup, with full **reboot persistence** and **conflict prevention**.

## Key Features

### 🔄 Reboot Persistence
- **State Management**: Maintains execution state across system reboots
- **Systemd Integration**: Creates temporary service for automatic continuation
- **Stage Tracking**: Resumes from exact point after reboot interruption

### 🚫 Conflict Prevention
- **Single Execution Point**: Eliminates race conditions with other boot scripts
- **Lock File Management**: Prevents concurrent executions
- **Unified Pipeline**: Consolidates all provisioning operations

### 📊 Stage-Based Architecture
1. **INIT** - System detection and setup
2. **BANNER** - Set login banners and MOTD
3. **UPDATES** - Install system updates/upgrades
4. **POST-REBOOT** - Post-update validation
5. **ZABBIX-INSTALL** - Install Zabbix agent
6. **ZABBIX-CONFIGURE** - Configure for tunnel connectivity
7. **TUNNEL-SETUP** - Create SSH tunnel service
8. **COMPLETE** - Finalize and cleanup

## Virtualizor Integration

### Recipe Setup
```bash
#!/bin/bash
# Virtualizor Recipe Script
# Place in your Virtualizor recipe configuration

# Download and execute master script
wget -O /tmp/virtualizor-server-setup.sh https://your-repo/scripts/virtualizor-server-setup.sh
chmod +x /tmp/virtualizor-server-setup.sh

# Execute with custom parameters
/tmp/virtualizor-server-setup.sh \
    --banner-text "YourCompany Managed Server" \
    --zabbix-version "6.4" \
    --ssh-host "monitor.yourcompany.com"
```

### Execution Flow
```
Virtualizor Recipe Start
         ↓
  virtualizor-server-setup.sh
         ↓
   [INIT] System Detection
         ↓
   [BANNER] Login Messages
         ↓
   [UPDATES] System Updates
         ↓
   [REBOOT] → [Systemd Service] → [Resume]
         ↓
   [POST-REBOOT] Validation
         ↓
   [ZABBIX-INSTALL] Agent Install
         ↓
   [ZABBIX-CONFIGURE] Tunnel Config
         ↓
   [TUNNEL-SETUP] SSH Service
         ↓
   [COMPLETE] Cleanup & Ready
         ↓
  Server Ready for User Access
```

## Usage Examples

### Basic Virtualizor Execution
```bash
# Default execution (recommended for recipes)
./virtualizor-server-setup.sh
```

### Custom Configuration
```bash
# Custom banner and Zabbix settings
./virtualizor-server-setup.sh \
    --banner-text "Production Server - Do Not Modify" \
    --zabbix-version "6.4" \
    --ssh-host "zabbix.company.com"
```

### Manual Stage Control
```bash
# Start from specific stage
./virtualizor-server-setup.sh --stage zabbix-install

# Resume after reboot (automatic via systemd)
./virtualizor-server-setup.sh --resume-after-reboot

# Check current status
./virtualizor-server-setup.sh --status

# Test configuration without changes
./virtualizor-server-setup.sh --test
```

### Recovery Operations
```bash
# Show current setup status
./virtualizor-server-setup.sh --status

# Clean up after failed execution
./virtualizor-server-setup.sh --cleanup
```

## State Management

### State Files
- **State File**: `/var/run/virtualizor-server-setup.state`
- **Reboot Flag**: `/var/run/virtualizor-server-setup.reboot`
- **Lock File**: `/var/run/virtualizor-server-setup.pid`

### State Information
```bash
# View current state
cat /var/run/virtualizor-server-setup.state
```

Output example:
```
CURRENT_STAGE="zabbix-install"
EXECUTION_START="2025-07-21 10:30:15"
STAGE_DATA="updates_installed=true"
SCRIPT_PID=1234
HOSTNAME="web-server-01"
```

## Reboot Handling

### Automatic Process
1. **Update Stage**: Detects updates requiring reboot
2. **State Save**: Records next stage in state file
3. **Service Create**: Creates systemd service for continuation
4. **Reboot Schedule**: Initiates system reboot
5. **Service Execute**: Systemd runs script after reboot
6. **State Resume**: Continues from saved stage
7. **Service Remove**: Cleans up temporary service

### Manual Intervention
```bash
# If reboot doesn't continue automatically
systemctl status virtualizor-server-setup.service

# Manual resume
./virtualizor-server-setup.sh --resume-after-reboot

# Force restart from beginning
./virtualizor-server-setup.sh --cleanup
./virtualizor-server-setup.sh
```

## Configuration Options

### Default Settings (Embedded)
```bash
# Banner settings
DEFAULT_BANNER_TEXT="Virtualizor Managed Server - Setup in Progress"
DEFAULT_BANNER_COLOR="red"
DEFAULT_MOTD_MESSAGE="This server is managed by Virtualizor and monitored by Zabbix"

# Zabbix settings
DEFAULT_ZABBIX_VERSION="6.4"
DEFAULT_ZABBIX_SERVER="127.0.0.1"

# Banner settings
DEFAULT_BANNER_TEXT="Virtualizor Managed Server - Setup in Progress"
DEFAULT_BANNER_COLOR="red"
DEFAULT_MOTD_MESSAGE="WARNING: Authorized Access Only
*   This VPS is the property of Everything Cloud Solutions *
*   Unauthorized use is strictly prohibited and monitored. *
*   For any issue, report it to support@everythingcloud.ca *"

# Zabbix settings
DEFAULT_ZABBIX_VERSION="6.4"
DEFAULT_ZABBIX_SERVER="127.0.0.1"

# SSH tunnel settings
DEFAULT_HOME_SERVER_IP="monitor.cloudgeeks.in"
DEFAULT_HOME_SERVER_SSH_PORT=20202
DEFAULT_ZABBIX_SERVER_PORT=10051
DEFAULT_SSH_USER="zabbixssh"
DEFAULT_SSH_KEY="/root/.ssh/zabbix_tunnel_key"
DEFAULT_ADMIN_USER="root"
DEFAULT_ADMIN_KEY="/root/.ssh/id_rsa"
```

### Customization
Modify the embedded configuration section at the top of the script:
```bash
# Edit the script directly
nano virtualizor-server-setup.sh

# Find and modify the configuration section:
readonly DEFAULT_HOME_SERVER_IP="your-monitor-server.com"
readonly DEFAULT_HOME_SERVER_SSH_PORT=22022
readonly DEFAULT_SSH_USER="yourtunneluser"
```

## Logging and Monitoring

### Log Locations
- **Setup Logs**: `/var/log/zabbix-scripts/virtualizor-server-setup-YYYYMMDD.log`
- **Systemd Logs**: `journalctl -u virtualizor-server-setup.service`
- **Zabbix Logs**: `/var/log/zabbix/zabbix_agentd.log`
- **Tunnel Logs**: `journalctl -u zabbix-tunnel.service`

### Monitoring Commands
```bash
# Watch setup progress
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Check service status
systemctl status virtualizor-server-setup.service
systemctl status zabbix-agent
systemctl status zabbix-tunnel

# View recent activity
journalctl -u virtualizor-server-setup.service --since "1 hour ago"
```

## SSH Tunnel Setup

### Automatic Key Generation
The script automatically generates SSH keys if they don't exist:
```bash
# Location: /root/.ssh/zabbix_tunnel_key
# Public key: /root/.ssh/zabbix_tunnel_key.pub
```

### Manual Key Setup Required
After script execution, **manual SSH key setup is required**:

1. **Copy Public Key**: From script output or log file
2. **Remote Server Setup**: 
   ```bash
   # On monitoring server (monitor.cloudgeeks.in)
   useradd -r -s /bin/bash -m zabbixssh
   mkdir -p /home/zabbixssh/.ssh
   echo "RESTRICTIONS ssh-rsa AAAAB3N..." > /home/zabbixssh/.ssh/authorized_keys
   chown -R zabbixssh:zabbixssh /home/zabbixssh/.ssh
   chmod 700 /home/zabbixssh/.ssh
   chmod 600 /home/zabbixssh/.ssh/authorized_keys
   ```

3. **Start Tunnel Service**:
   ```bash
   systemctl start zabbix-tunnel
   systemctl status zabbix-tunnel
   ```

## Troubleshooting

### Common Issues

#### Script Won't Start
```bash
# Check for existing execution
ps aux | grep virtualizor-server-setup
cat /var/run/virtualizor-server-setup.pid

# Clean up and retry
./virtualizor-server-setup.sh --cleanup
./virtualizor-server-setup.sh
```

#### Stuck After Reboot
```bash
# Check systemd service
systemctl status virtualizor-server-setup.service
journalctl -u virtualizor-server-setup.service

# Manual resume
./virtualizor-server-setup.sh --resume-after-reboot
```

#### Updates Fail
```bash
# Check package manager logs
# For Ubuntu/Debian:
cat /var/log/apt/history.log

# For RHEL/CentOS:
cat /var/log/yum.log
# or
cat /var/log/dnf.log

# Retry from updates stage
./virtualizor-server-setup.sh --stage updates
```

#### Zabbix Installation Fails
```bash
# Check Zabbix repository access
wget -q --spider https://repo.zabbix.com/

# Manual repository setup
./virtualizor-server-setup.sh --stage zabbix-install

# Check agent status
systemctl status zabbix-agent
zabbix_agentd -t -c /etc/zabbix/zabbix_agentd.conf
```

#### SSH Tunnel Issues
```bash
# Check SSH key
ls -la /root/.ssh/zabbix_tunnel_key*

# Test SSH connectivity
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Check tunnel service
systemctl status zabbix-tunnel
journalctl -u zabbix-tunnel --lines 50
```

### Debug Mode
Enable debug logging by modifying the script:
```bash
# Add at the beginning of main()
set -x  # Enable debug tracing
```

### Emergency Recovery
```bash
# Complete cleanup and restart
./virtualizor-server-setup.sh --cleanup
rm -f /var/run/virtualizor-server-setup.*
systemctl stop virtualizor-server-setup.service
systemctl disable virtualizor-server-setup.service
rm -f /etc/systemd/system/virtualizor-server-setup.service
systemctl daemon-reload

# Start fresh
./virtualizor-server-setup.sh
```

## Best Practices

### For Virtualizor Admins
1. **Test in Staging**: Always test script changes in non-production environment
2. **Monitor Execution**: Watch logs during initial deployments
3. **Backup Configurations**: Keep copies of customized versions
4. **Document Changes**: Track any modifications to default settings

### For System Administrators
1. **Network Requirements**: Ensure reliable internet connectivity for package downloads
2. **SSH Key Management**: Prepare tunnel user accounts on monitoring servers
3. **Firewall Configuration**: Allow SSH connections on custom ports
4. **Log Retention**: Configure log rotation for script and service logs

### For Developers
1. **Stage Isolation**: Each stage should be idempotent and resumable
2. **Error Handling**: All operations must include proper error handling
3. **State Validation**: Verify state consistency before stage transitions
4. **Resource Cleanup**: Ensure proper cleanup on success and failure

## Integration with Other Systems

### Virtualizor Recipe Templates
```bash
# Basic recipe template
#!/bin/bash
set -euo pipefail

# Download setup script
SETUP_SCRIPT="/tmp/virtualizor-server-setup.sh"
wget -O "$SETUP_SCRIPT" "https://your-repo/scripts/virtualizor-server-setup.sh"
chmod +x "$SETUP_SCRIPT"

# Execute with organization settings
"$SETUP_SCRIPT" \
    --banner-text "ACME Corp Managed Server" \
    --ssh-host "monitor.acme.com" \
    --zabbix-version "6.4"
```

### Configuration Management
```bash
# Ansible playbook integration
- name: Execute Virtualizor setup
  script: virtualizor-server-setup.sh
  args:
    creates: /var/log/zabbix-scripts/virtualizor-server-setup-complete.flag

# Terraform integration
resource "null_resource" "server_setup" {
  provisioner "remote-exec" {
    script = "virtualizor-server-setup.sh"
  }
}
```

This master script provides a robust, production-ready solution for Virtualizor server provisioning with complete lifecycle management and conflict prevention.
