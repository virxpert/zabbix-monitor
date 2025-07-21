# Virtualizor Recipe Installation Guide

## Overview

This guide covers the integration of `virtualizor-server-setup.sh` into **Virtualizor software recipes** for automated server provisioning during VM/container creation.

## Quick Integration

### Basic Recipe Integration

Add this to your Virtualizor recipe's post-install script:

```bash
#!/bin/bash
# Virtualizor Recipe - Zabbix Monitoring Setup

# Download and execute master provisioning script
wget -O /tmp/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh

# Make executable
chmod +x /tmp/virtualizor-server-setup.sh

# Execute with default configuration
/tmp/virtualizor-server-setup.sh

# Recipe complete
exit 0
```

### Custom Configuration Recipe

For customized deployments:

```bash
#!/bin/bash
# Virtualizor Recipe - Custom Zabbix Monitoring Setup

# Download script
wget -O /tmp/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
chmod +x /tmp/virtualizor-server-setup.sh

# Execute with custom banner and settings
/tmp/virtualizor-server-setup.sh \
    --banner-text "Production Server - $(hostname)" \
    --ssh-host "monitor.yourcompany.com" \
    --ssh-port 22202

exit 0
```

## Virtualizor Configuration

### Recipe Settings

**Recipe Type**: Post-Installation Script
**Execution Environment**: Root user
**Script Timeout**: 30 minutes (to handle system reboots)
**Retry on Failure**: Yes

### Required Virtualizor Settings

```bash
# Set in Virtualizor recipe configuration
SCRIPT_TIMEOUT=1800      # 30 minutes
ALLOW_REBOOT=true        # Required for system updates
ROOT_EXECUTION=true      # Script must run as root
NETWORK_REQUIRED=true    # Needs internet for package downloads
```

## Network Requirements

### Outbound Connections Required

The script requires internet access during provisioning for:

1. **Package repositories** (port 80/443)
2. **Zabbix repository** (port 80/443)  
3. **SSH connection to monitoring server** (custom port, default 20202)

### Firewall Rules

Ensure the following ports are accessible:

```bash
# Outbound (during provisioning)
TCP 80/443    # Package downloads
TCP 20202     # SSH tunnel to monitoring server (customizable)

# Inbound (after provisioning)
TCP 22        # SSH administration  
TCP 10050     # Zabbix agent (via tunnel, not directly exposed)
```

## Script Customization

### Embedded Configuration

Modify these values in the script before deployment:

```bash
# SSH Tunnel Settings  
DEFAULT_HOME_SERVER_IP="monitor.yourcompany.com"
DEFAULT_HOME_SERVER_SSH_PORT=20202
DEFAULT_SSH_USER="zabbixssh"

# Company Branding
DEFAULT_MOTD_MESSAGE="WARNING: Authorized Access Only
*   This VPS is the property of Your Company Name *
*   Unauthorized use is strictly prohibited and monitored. *
*   For support contact: support@yourcompany.com *"

# Zabbix Configuration
DEFAULT_ZABBIX_VERSION="6.4"
DEFAULT_ZABBIX_SERVER_PORT=10051
```

### Command-Line Customization

For per-recipe customization without script modification:

```bash
/tmp/virtualizor-server-setup.sh \
    --banner-text "Customer Server - $(hostname)" \
    --motd-message "Property of Customer Name" \
    --ssh-host "customer-monitor.example.com" \
    --ssh-port 22202 \
    --zabbix-version "7.0"
```

## State Persistence

### Reboot Handling

The script automatically handles system reboots during the provisioning process:

1. **Before Reboot**: Saves current stage to `/var/run/virtualizor-server-setup.state`
2. **Creates systemd service** for post-reboot continuation
3. **After Reboot**: Automatically resumes from saved stage
4. **On Completion**: Cleans up temporary service and state files

### Manual Resume

If the recipe fails or is interrupted:

```bash
# Check current status
/tmp/virtualizor-server-setup.sh --status

# Resume from where it left off
/tmp/virtualizor-server-setup.sh --resume

# Start from specific stage if needed
/tmp/virtualizor-server-setup.sh --stage zabbix-install
```

## Monitoring Integration

### SSH Key Collection

After recipe completion, administrators need to collect SSH public keys:

```bash
# Connect to the new server
ssh root@new-server-ip

# Get the SSH public key for tunnel
cat /root/zabbix_tunnel_public_key.txt

# View complete setup instructions
cat /root/zabbix_ssh_key_info.txt
```

### Zabbix Server Configuration

Add the collected public key to your monitoring server:

```bash
# On monitoring server
echo "ssh-rsa AAAAB3NzaC1yc2E... zabbix-tunnel-hostname-date" >> /home/zabbixssh/.ssh/authorized_keys

# Restart tunnel service on agent server
systemctl start zabbix-tunnel
```

### Host Configuration

Add the new server to Zabbix web interface:
- **Host name**: Server hostname
- **Visible name**: Friendly display name
- **IP address**: `127.0.0.1` (via tunnel)
- **Port**: `10050`
- **Template**: Linux by Zabbix agent

## Troubleshooting

### Recipe Execution Issues

```bash
# Check recipe logs in Virtualizor
tail -f /var/log/virtualizor/recipes.log

# Check script logs on server
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Verify systemd service if reboot occurred
systemctl status virtualizor-server-setup.service
```

### Network Connectivity

```bash
# Test package repository access
curl -I http://packages.zabbix.com/

# Test SSH connectivity to monitoring server  
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.example.com

# Check DNS resolution
nslookup monitor.example.com
```

### Permission Issues

```bash
# Verify script permissions
ls -la /tmp/virtualizor-server-setup.sh

# Check log directory
ls -la /var/log/zabbix-scripts/

# Verify SSH key permissions
ls -la /root/.ssh/zabbix_tunnel_key*
```

## Best Practices

### Recipe Design

1. **Timeout Settings**: Allow sufficient time for reboots (30+ minutes)
2. **Error Handling**: Enable retry on failure in Virtualizor
3. **Logging**: Monitor recipe execution through Virtualizor logs
4. **Testing**: Test recipes in development environment first

### Security Considerations

1. **Script Source**: Use trusted sources or internal mirrors
2. **Network Access**: Restrict outbound connections where possible
3. **Key Management**: Collect SSH keys promptly after provisioning
4. **User Access**: Disable unnecessary user accounts post-setup

### Operational Workflow

1. **Pre-deployment**: Configure monitoring server with SSH user
2. **Recipe Execution**: Deploy VMs with recipe
3. **Post-deployment**: Collect SSH keys and configure Zabbix hosts
4. **Verification**: Test monitoring connectivity and data collection

This approach ensures consistent, automated Zabbix monitoring setup across all Virtualizor-provisioned servers with minimal manual intervention.
