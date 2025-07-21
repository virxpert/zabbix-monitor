# Administrator Guide: Accessing SSH Keys During Provisioning

## Overview

During Virtualizor server provisioning, the master script (`virtualizor-server-setup.sh`) generates SSH keys for the Zabbix monitoring tunnel. This guide explains how administrators can access these keys during and after the provisioning process.

## SSH Key Access Methods

### 1. Console Output During Provisioning

The script displays the SSH key prominently when it's generated and at completion:

```bash
==================== ADMINISTRATOR ACTION REQUIRED ====================
SSH KEY GENERATED - MUST BE ADDED TO ZABBIX SERVER
========================================================================
COPY THIS SSH PUBLIC KEY TO YOUR ZABBIX SERVER:
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... zabbix-tunnel-hostname-20250721
========================================================================
```

### 2. Saved Key Files (Available Immediately)

The script automatically saves SSH keys to accessible locations:

```bash
# View complete setup instructions
cat /root/zabbix_ssh_key_info.txt

# View just the public key
cat /root/zabbix_tunnel_public_key.txt

# View the raw public key file
cat /root/.ssh/zabbix_tunnel_key.pub
```

### 3. Log Files (Permanent Record)

SSH key information is logged with clear markers:

```bash
# View setup logs
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Search for SSH key entries
grep -A5 -B5 "SSH.*key\|public key" /var/log/zabbix-scripts/virtualizor-server-setup-*.log
```

### 4. Status Commands (Anytime Access)

```bash
# Quick status with SSH key information
./virtualizor-server-setup.sh --status

# Detailed system validation
./virtualizor-server-setup.sh --validate
```

## File Locations Reference

| File | Purpose | Content |
|------|---------|---------|
| `/root/zabbix_ssh_key_info.txt` | Complete instructions | Full setup guide with all commands |
| `/root/zabbix_tunnel_public_key.txt` | Public key only | Ready to copy to Zabbix server |
| `/root/.ssh/zabbix_tunnel_key` | Private key | Used by tunnel service (600 permissions) |
| `/root/.ssh/zabbix_tunnel_key.pub` | Public key | Source file for tunnel setup |

## Virtualizor Integration Workflow

### During Recipe Execution

1. **Virtualizor starts server provisioning**
2. **Script generates SSH keys** → Keys saved to accessible locations
3. **Script displays key on console** → Visible in Virtualizor logs/console
4. **Script completes setup** → MOTD updated with key location info

### Administrator Actions Post-Provisioning

1. **Access the server via SSH/console**
2. **Retrieve the public key**:
   ```bash
   cat /root/zabbix_tunnel_public_key.txt
   ```
3. **Add key to Zabbix server** (see server configuration guide)
4. **Start the tunnel**:
   ```bash
   systemctl start zabbix-tunnel
   ```

## Automation-Friendly Access

### For Scripts/Automation Tools

```bash
#!/bin/bash
# Retrieve SSH public key for automation
SERVER_IP="$1"
PUBLIC_KEY=$(ssh root@$SERVER_IP "cat /root/zabbix_tunnel_public_key.txt" 2>/dev/null)

if [ -n "$PUBLIC_KEY" ]; then
    echo "Retrieved SSH key for server $SERVER_IP:"
    echo "$PUBLIC_KEY"
else
    echo "Failed to retrieve SSH key from server $SERVER_IP"
    exit 1
fi
```

### For Configuration Management

```yaml
# Ansible example
- name: Retrieve Zabbix SSH public key
  command: cat /root/zabbix_tunnel_public_key.txt
  register: zabbix_ssh_key

- name: Display retrieved key
  debug:
    msg: "SSH Key: {{ zabbix_ssh_key.stdout }}"
```

## MOTD Integration

After completion, the SSH key location is shown in the login banner:

```
===============================================
   VIRTUALIZOR MANAGED SERVER - READY
===============================================
   Hostname: web-server-01
   Setup Completed: 2025-07-21 10:30:45
   
   Status: Server Ready for Use
   Zabbix Agent: Configured and Running
   SSH Tunnel: Generated - Manual setup required
   SSH Key Setup: cat /root/zabbix_ssh_key_info.txt
   Start Tunnel:  systemctl start zabbix-tunnel
===============================================
```

## Security Considerations

### Key Protection

- **Private keys**: 600 permissions, root-only access
- **Public keys**: 644 permissions, readable but not writable
- **Info files**: Root-readable, contain no private information

### Access Control

- All key files stored in `/root/` - requires root access
- SSH keys use strong RSA 4096-bit encryption
- Keys include hostname and date in comment for identification

### Audit Trail

- All key generation logged with timestamps
- SSH key content logged for audit purposes
- File creation and permission changes recorded

## Troubleshooting

### Key Files Missing

```bash
# Regenerate SSH key if missing
./virtualizor-server-setup.sh --stage tunnel-setup
```

### Cannot Access Files

```bash
# Check file permissions
ls -la /root/zabbix_*

# Verify root access
whoami
```

### Key Not Working

```bash
# Test SSH key manually
ssh -i /root/.ssh/zabbix_tunnel_key -p your-ssh-port your-ssh-user@your-monitor-server.com

# Check key format
ssh-keygen -l -f /root/.ssh/zabbix_tunnel_key.pub
```

## Integration with Provisioning Tools

### Virtualizor Recipe Access

```bash
# Add to recipe post-execution script
echo "SSH Key for Zabbix tunnel:"
cat /root/zabbix_tunnel_public_key.txt || echo "SSH key not generated yet"
```

### Proxmox Integration

```bash
# Add to cloud-init or startup script
if [ -f "/root/zabbix_tunnel_public_key.txt" ]; then
    echo "=== ZABBIX SSH KEY ==="
    cat /root/zabbix_tunnel_public_key.txt
fi
```

This approach ensures administrators always have multiple ways to access the SSH key information, whether during provisioning, immediately after, or at any time during the server's lifecycle.
