# Zabbix Scripts & Utilities - Usage Guide

## Multi-Server Architecture Overview

This system supports **unlimited 1-to-many monitoring** where one Zabbix server monitors any number of guest servers through encrypted SSH tunnels.

```
[Guest Server 1] ----SSH Tunnel----> [Monitor Server:20202] --> [Zabbix Server:10051]
[Guest Server 2] ----SSH Tunnel----> [Monitor Server:20202] --> [Zabbix Server:10051]  
[Guest Server 3] ----SSH Tunnel----> [Monitor Server:20202] --> [Zabbix Server:10051]
[Guest Server N] ----SSH Tunnel----> [Monitor Server:20202] --> [Zabbix Server:10051]
```

**Key Benefits:**
- **Unlimited Scaling**: Monitor hundreds of servers from one Zabbix instance
- **Individual Security**: Each server has unique SSH key pair
- **Central Management**: Single monitoring server handles all connections
- **Network Flexibility**: Works across complex network topologies

## SSH Tunnel Architecture Details

### Traditional vs Multi-Server Architecture

**Single Server Flow:**
```
[Agent Server] --SSH Tunnel--> [Monitoring Server] --Local--> [Zabbix Server]
    :10050                         :20202                        :10051
```

**Multi-Server Flow:**
```
[Guest 1 :10050] --SSH--> [Monitor :20202] --Local--> [Zabbix :10051]
[Guest 2 :10050] --SSH--> [Monitor :20202] --Local--> [Zabbix :10051]
[Guest N :10050] --SSH--> [Monitor :20202] --Local--> [Zabbix :10051]
```

## Automated Setup (via Master Script)

### Multiple Server Deployment

**Deploy to Multiple Servers:**
```bash
# Deploy to server 1
./virtualizor-server-setup.sh --banner-text "Production Web Server 1"

# Deploy to server 2  
./virtualizor-server-setup.sh --banner-text "Production Database Server"

# Deploy to server N
./virtualizor-server-setup.sh --banner-text "Application Server 5"
```

Each execution generates **unique SSH keys** and tunnel configuration for secure multi-server monitoring.

### Basic Single Server Usage

```bash
# Complete automated setup with defaults
./virtualizor-server-setup.sh

# The script automatically:
# 1. Generates SSH key pair
# 2. Configures Zabbix agent for tunnel
# 3. Creates systemd service for tunnel
# 4. Displays public key for manual server setup
```

### Custom Configuration

```bash
# Custom monitoring server and settings
./virtualizor-server-setup.sh \
    --ssh-host "monitor.example.com" \
    --ssh-port 22202 \
    --ssh-user "zabbixssh" \
    --zabbix-version "6.4"
```

## Manual Configuration

### Agent Server Setup

#### 1. Generate SSH Key

```bash
# Create SSH key for tunnel
ssh-keygen -t rsa -b 4096 -f /root/.ssh/zabbix_tunnel_key -N "" -C "zabbix-tunnel-$(hostname)-$(date +%Y%m%d)"

# Set proper permissions
chmod 600 /root/.ssh/zabbix_tunnel_key
chmod 644 /root/.ssh/zabbix_tunnel_key.pub

# Display public key for server setup
cat /root/.ssh/zabbix_tunnel_key.pub
```

#### 2. Configure Zabbix Agent

```bash
# Edit Zabbix agent configuration
vim /etc/zabbix/zabbix_agentd.conf

# Key settings for tunnel mode
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=$(hostname)
```

#### 3. Create Tunnel Service

```bash
# Create systemd service file
cat > /etc/systemd/system/zabbix-tunnel.service << 'EOF'
[Unit]
Description=Persistent SSH Reverse Tunnel to Zabbix Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 60
ExecStart=/usr/bin/ssh -i /root/.ssh/zabbix_tunnel_key \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    -N -R 10051:localhost:10051 \
    -p 20202 \
    zabbixssh@monitor.example.com
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable zabbix-tunnel
```

### Monitoring Server Setup

#### 1. Create SSH User

```bash
# Create dedicated user for SSH tunnels
useradd -r -s /bin/bash -m zabbixssh
mkdir -p /home/zabbixssh/.ssh
chmod 700 /home/zabbixssh/.ssh
```

#### 2. Configure SSH Keys

```bash
# Add agent public keys to authorized_keys
echo 'command="echo '\''Tunnel only'\''",no-agent-forwarding,no-X11-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2E...' >> /home/zabbixssh/.ssh/authorized_keys

# Set proper permissions
chown -R zabbixssh:zabbixssh /home/zabbixssh/.ssh
chmod 600 /home/zabbixssh/.ssh/authorized_keys
```

#### 3. SSH Server Configuration

```bash
# Edit SSH daemon configuration
vim /etc/ssh/sshd_config

# Required settings
Port 20202
AllowTcpForwarding yes
GatewayPorts no
AllowUsers zabbixssh
PasswordAuthentication no
PubkeyAuthentication yes

# Restart SSH service
systemctl restart sshd
```

#### 4. Firewall Configuration

```bash
# Allow SSH on custom port
ufw allow 20202/tcp comment "SSH for Zabbix tunnels"

# Allow Zabbix server port locally
ufw allow from 127.0.0.1 to any port 10051 comment "Zabbix server local"
```

## Service Management

### Agent Server Operations

```bash
# Start tunnel service
systemctl start zabbix-tunnel

# Check tunnel status
systemctl status zabbix-tunnel

# View tunnel logs
journalctl -u zabbix-tunnel -f

# Test tunnel connectivity
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.example.com

# Restart services
systemctl restart zabbix-agent zabbix-tunnel
```

### Monitoring Server Operations

```bash
# Check SSH connections
ss -tlnp | grep :20202

# View SSH logs
tail -f /var/log/auth.log | grep zabbixssh

# Monitor active tunnels
netstat -tlnp | grep 10051

# Check Zabbix server connectivity
telnet localhost 10051
```

## Configuration Options

### SSH Tunnel Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `-R 10051:localhost:10051` | Reverse port forward | Required | Forwards agent traffic |
| `-o ServerAliveInterval=60` | Keepalive interval | 60 seconds | Prevents connection drops |
| `-o ServerAliveCountMax=3` | Max missed keepalives | 3 | Triggers reconnection |
| `-o ExitOnForwardFailure=yes` | Exit if forward fails | Yes | Ensures service restart |
| `-o BatchMode=yes` | Non-interactive mode | Yes | Required for service |
| `-N` | No shell execution | Required | Tunnel only |

### Zabbix Agent Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `Server` | `127.0.0.1` | Accept connections from tunnel |
| `ServerActive` | `127.0.0.1` | Send data to tunnel endpoint |
| `ListenPort` | `10050` | Standard Zabbix agent port |
| `Hostname` | `$(hostname)` | Server identification |

## Security Considerations

### SSH Key Security

1. **Strong Keys**: Use RSA 4096-bit or ED25519 keys
2. **Key Rotation**: Regularly rotate SSH keys (quarterly/yearly)
3. **Access Control**: Restrict key file permissions (600)
4. **Unique Keys**: Generate unique keys per server

### SSH Configuration

1. **Restricted Commands**: Use `command=""` in authorized_keys
2. **No Shell Access**: Disable shell/pty for tunnel user
3. **Port Security**: Use non-standard SSH ports
4. **Connection Limits**: Limit connections per user/IP

### Network Security

1. **Firewall Rules**: Restrict SSH access to necessary IPs
2. **Tunnel Encryption**: All traffic encrypted by SSH
3. **Local Binding**: Bind forwarded ports to localhost only
4. **Monitoring**: Log and monitor SSH connection attempts

## Troubleshooting

### Connection Issues

```bash
# Test SSH connectivity manually
ssh -vvv -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.example.com

# Check network connectivity
telnet monitor.example.com 20202

# Verify DNS resolution
nslookup monitor.example.com

# Test port forwarding
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 -R 10051:localhost:10051 zabbixssh@monitor.example.com -N
```

### Service Issues

```bash
# Check service status
systemctl status zabbix-tunnel zabbix-agent

# View detailed logs
journalctl -u zabbix-tunnel --since "1 hour ago"

# Test Zabbix connectivity
zabbix_agentd -t system.hostname

# Check process status
ps aux | grep ssh | grep zabbix
```

### Permission Issues

```bash
# Verify SSH key permissions
ls -la /root/.ssh/zabbix_tunnel_key*

# Check SSH user permissions (monitoring server)
ls -la /home/zabbixssh/.ssh/

# Test SSH key format
ssh-keygen -l -f /root/.ssh/zabbix_tunnel_key.pub
```

### Port Conflicts

```bash
# Check port usage
ss -tlnp | grep -E "(10050|10051|20202)"

# Find process using port
lsof -i :10051

# Kill conflicting processes
pkill -f "port 10051"
```

## Advanced Configuration

### Multiple Monitoring Servers

```bash
# Configure failover tunnels
ExecStart=/usr/bin/ssh -i /root/.ssh/zabbix_tunnel_key \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=30 \
    -N -R 10051:localhost:10051 \
    -p 20202 zabbixssh@primary.example.com
    
ExecStartPost=/bin/sleep 10
ExecStartPost=/usr/bin/ssh -i /root/.ssh/zabbix_tunnel_key \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=30 \
    -N -R 10051:localhost:10051 \
    -p 20202 zabbixssh@backup.example.com
```

### Custom Port Configuration

```bash
# Non-standard Zabbix ports
ExecStart=/usr/bin/ssh -i /root/.ssh/zabbix_tunnel_key \
    -N -R 10061:localhost:10050 \
    -p 22202 zabbixssh@monitor.example.com

# Update Zabbix configuration
Server=127.0.0.1
ListenPort=10050
```

### Monitoring Integration

```bash
# Health check script
#!/bin/bash
if ! systemctl is-active zabbix-tunnel >/dev/null; then
    echo "Tunnel down, restarting..."
    systemctl restart zabbix-tunnel
fi

# Add to cron for automatic recovery
echo "*/5 * * * * /root/check_tunnel.sh" | crontab -
```

This comprehensive guide covers all aspects of SSH tunnel configuration for Zabbix monitoring, from automated setup to advanced troubleshooting scenarios.

## Recent Improvements (July 2025)

### Enhanced Reliability

**Systemd Service Improvements:**

- Absolute path resolution in service files prevents execution failures
- Automatic permission validation ensures services start properly
- Enhanced error handling for service creation and management

**Quality Assurance Enhancements:**

- Comprehensive syntax validation before script execution
- Variable consistency checks prevent runtime errors
- Improved logging for better troubleshooting

**Previous Issues Resolved:**

- Fixed `exit code 203/EXEC` errors in systemd services
- Resolved unbound variable issues in Zabbix configuration
- Standardized path references throughout all scripts

**Usage Impact:**

- Scripts now more reliable in automated environments
- Better error reporting for faster issue resolution
- Improved state persistence across system reboots

For detailed troubleshooting of these improvements, see [Troubleshooting Guide](troubleshooting-guide.md).
