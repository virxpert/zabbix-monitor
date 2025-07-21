# Zabbix Server Configuration for Multi-Server SSH Tunnel Monitoring

This document provides step-by-step instructions for configuring **one Zabbix server** to monitor **unlimited guest servers** via SSH reverse tunnels.

## Multi-Server Architecture Overview

The Virtualizor server setup script establishes SSH reverse tunnels from multiple guest servers to a single monitoring server. This enables **1-to-many monitoring** where one Zabbix instance can monitor hundreds of servers securely.

### Architecture Diagram

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Guest Server  │    │   Guest Server  │    │   Guest Server  │
│       #1        │    │       #2        │    │       #N        │
│  Zabbix Agent   │    │  Zabbix Agent   │    │  Zabbix Agent   │
│  :10050         │    │  :10050         │    │  :10050         │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │ SSH Tunnel           │ SSH Tunnel           │ SSH Tunnel  
          │ (unique key)         │ (unique key)         │ (unique key)
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Monitor Server                               │
│  SSH User: zabbixssh  Port: 20202                             │
│  ┌─────────────────┐                                          │
│  │  Zabbix Server  │◄── Queries: 127.0.0.1:10050             │
│  │  :10051         │    (all guests via localhost)            │
│  └─────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Key Benefits:**
- **Unlimited Scaling**: One Zabbix server monitors any number of guests
- **Individual Security**: Each server uses unique SSH key pairs
- **Central Management**: Single monitoring configuration for all servers
- **Network Security**: No exposed ports, encrypted tunnel connections

## Server Configuration Requirements

### Homelab Network Setup
- **Zabbix Server**: Running in homelab behind router/firewall
- **Domain**: `monitor.cloudgeeks.in` (points to your public IP)  
- **Router NAT**: External port `20202` → Internal server port `22`
- **Security**: Zabbix ports (10050/10051) remain internal only
- **SSH User**: `zabbixssh` for tunnel connections
- **Tunnel Traffic**: All Zabbix communication via encrypted SSH tunnels

## Step 1: SSH User Setup on Zabbix Server

### Create SSH User for Tunnels

```bash
# On the Zabbix server (monitor.cloudgeeks.in)
sudo useradd -m -s /bin/bash zabbixssh
sudo mkdir -p /home/zabbixssh/.ssh
sudo chmod 700 /home/zabbixssh/.ssh
sudo touch /home/zabbixssh/.ssh/authorized_keys
sudo chmod 600 /home/zabbixssh/.ssh/authorized_keys
sudo chown -R zabbixssh:zabbixssh /home/zabbixssh/.ssh
```

### Configure SSH for Tunnel User

**Important**: Since you're using NAT (20202 → 22), configure SSH on the internal server to use standard port 22.

```bash
# Edit SSH configuration on the homelab server
sudo nano /etc/ssh/sshd_config
```

Add or modify these settings:

```bash
# Keep standard SSH port (22) - Router NAT handles external port mapping
Port 22

# Allow both root and zabbixssh users
AllowUsers root zabbixssh

# Enable TCP forwarding for tunnels
AllowTcpForwarding yes
GatewayPorts yes

# Optional: Restrict zabbixssh user to only tunneling
Match User zabbixssh
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
```

Restart SSH service:
```bash
sudo systemctl restart sshd
```

## Step 2: Firewall Configuration

### Configure Internal Server Firewall

**Important**: Only configure the internal server firewall. Do NOT forward Zabbix ports on your router.

```bash
# Allow SSH connections (tunnels will connect to this)
sudo ufw allow 22/tcp

# Allow Zabbix ports for localhost connections only (tunnels use these)
sudo ufw allow from 127.0.0.1 to any port 10050
sudo ufw allow from 127.0.0.1 to any port 10051

# Optional: Allow from internal network if needed
# sudo ufw allow from 192.168.1.0/24 to any port 10050
# sudo ufw allow from 192.168.1.0/24 to any port 10051

# Reload firewall
sudo ufw reload
```

### Router/NAT Configuration (One-time Setup)

Configure your router to forward external SSH traffic to your internal Zabbix server:

```text
Router NAT/Port Forwarding Rule:
External Port: 20202
Internal IP: [your-zabbix-server-ip] 
Internal Port: 22
Protocol: TCP
```

**Security Note**: 
- ✅ **DO** forward port 20202 → 22 for SSH tunnels
- ❌ **DO NOT** forward ports 10050 or 10051 - this would expose Zabbix to the internet
- 🔒 All Zabbix traffic flows through encrypted SSH tunnels

### Verify Port Availability

```bash
# Check if ports are listening
netstat -tlnp | grep -E ':(20202|10051)'
ss -tlnp | grep -E ':(20202|10051)'
```

## Step 3: Add Agent Public Keys

When the Virtualizor setup script runs, it generates SSH keys and displays the public key. You need to add these to the server.

### Example Public Key Addition

```bash
# The script will display something like:
# ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... zabbix-tunnel-hostname-20250721

# Add the public key to authorized_keys
sudo nano /home/zabbixssh/.ssh/authorized_keys
```

Add each agent's public key on a new line:

```bash
# Example authorized_keys content
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...xyz zabbix-tunnel-server01-20250721
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...abc zabbix-tunnel-server02-20250721
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...def zabbix-tunnel-server03-20250721
```

### Secure the authorized_keys File

```bash
sudo chmod 600 /home/zabbixssh/.ssh/authorized_keys
sudo chown zabbixssh:zabbixssh /home/zabbixssh/.ssh/authorized_keys
```

## Step 4: Zabbix Server Configuration

### Configure Zabbix Server for Tunnel Connections

Edit the Zabbix server configuration:

```bash
sudo nano /etc/zabbix/zabbix_server.conf
```

Key settings for tunnel support:

```ini
# Listen on all interfaces to accept tunnel connections
ListenIP=0.0.0.0

# Default Zabbix server port
ListenPort=10051

# Source IP range (optional - restrict to localhost for tunnels)
# SourceIP=127.0.0.1

# Enable active checks
StartPollers=5
StartPollersUnreachable=1
StartTrappers=5
StartPingers=1

# Database connection settings (adjust as needed)
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=your_db_password

# Log settings
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=10
DebugLevel=3
```

Restart Zabbix server:

```bash
sudo systemctl restart zabbix-server
sudo systemctl status zabbix-server
```

## Step 5: Host Configuration in Zabbix Web Interface

### Add Hosts for Tunnel Connections

1. **Access Zabbix Web Interface**
   - URL: `http://monitor.cloudgeeks.in/zabbix`
   - Default credentials: Admin/zabbix

2. **Create Host Group** (optional)
   - Go to Configuration → Host groups
   - Create group: "Virtualizor Servers"

3. **Add New Host**
   - Go to Configuration → Hosts
   - Click "Create host"

4. **Host Configuration**
   ```
   Host name: server-hostname
   Visible name: Server Hostname (Everything Cloud Solutions)
   Groups: Virtualizor Servers
   Interfaces:
     - Type: Agent
     - IP address: 127.0.0.1  (tunnel endpoint)
     - DNS name: (leave blank)
     - Port: 10050
   ```

5. **Templates**
   - Add relevant templates (e.g., "Linux by Zabbix agent")

## Step 6: Testing and Validation

### Test SSH Tunnel Connection

From the agent server (after setup):

```bash
# Test SSH connection
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Test with tunnel parameters
ssh -i /root/.ssh/zabbix_tunnel_key \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    -N -R 10051:localhost:10051 \
    -p 20202 \
    zabbixssh@monitor.cloudgeeks.in
```

### Verify Zabbix Connectivity

On the Zabbix server:

```bash
# Check if Zabbix server is receiving data
tail -f /var/log/zabbix/zabbix_server.log | grep -i "connection"

# Test agent connectivity (when tunnel is active)
zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname

# Check active tunnels
netstat -tlnp | grep :10051
```

### Monitor Tunnel Status

```bash
# Check active SSH connections
sudo netstat -anp | grep :20202 | grep ESTABLISHED

# Monitor Zabbix server logs
sudo journalctl -u zabbix-server -f

# Check tunnel processes
ps aux | grep ssh | grep zabbixssh
```

## Step 7: Troubleshooting

### Common Issues and Solutions

#### SSH Connection Refused

```bash
# Check SSH service status
sudo systemctl status sshd

# Verify SSH configuration
sudo sshd -T | grep -E '(Port|AllowUsers|AllowTcpForwarding)'

# Check firewall
sudo ufw status
```

#### Zabbix Server Not Receiving Data

```bash
# Check Zabbix server status
sudo systemctl status zabbix-server

# Verify database connection
mysql -u zabbix -p zabbix -e "SHOW TABLES;"

# Check server configuration
sudo zabbix_server -t
```

#### Tunnel Connection Issues

```bash
# Check tunnel service on agent
systemctl status zabbix-tunnel
journalctl -u zabbix-tunnel -f

# Test manual tunnel creation
ssh -vvv -i /root/.ssh/zabbix_tunnel_key -N -R 10051:localhost:10051 -p 20202 zabbixssh@monitor.cloudgeeks.in
```

## Step 8: Automation and Monitoring

### Monitor Tunnel Health

Create a monitoring script on the Zabbix server:

```bash
#!/bin/bash
# /usr/local/bin/check-tunnel-health.sh

# Check active SSH tunnels
tunnel_count=$(netstat -tlnp 2>/dev/null | grep ":10051 " | wc -l)

if [ $tunnel_count -eq 0 ]; then
    echo "WARNING: No active Zabbix tunnels detected"
    exit 1
else
    echo "OK: $tunnel_count active tunnel(s) detected"
    exit 0
fi
```

### Setup Log Rotation

```bash
# Configure log rotation for tunnel logs
sudo nano /etc/logrotate.d/zabbix-tunnels

# Add content:
/var/log/zabbix/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl reload zabbix-server > /dev/null 2>&1 || true
    endscript
}
```

## Security Considerations

### SSH Security

1. **Use Key-Based Authentication Only**
   ```bash
   # In /etc/ssh/sshd_config
   PasswordAuthentication no
   PubkeyAuthentication yes
   ```

2. **Restrict zabbixssh User**
   ```bash
   # Limit user to tunneling only
   Match User zabbixssh
       ForceCommand /bin/false
       AllowTcpForwarding yes
       X11Forwarding no
       AllowAgentForwarding no
   ```

3. **Monitor SSH Connections**
   ```bash
   # Add to /etc/rsyslog.conf
   auth,authpriv.*    /var/log/ssh.log
   
   # Monitor failed attempts
   tail -f /var/log/ssh.log | grep "Failed"
   ```

### Network Security

1. **Firewall Rules**
   - Only allow SSH (port 20202) from known agent IPs
   - Restrict Zabbix port (10051) to localhost only

2. **VPN/Private Network**
   - Consider using VPN for additional security layer
   - Implement network segmentation

## Maintenance Procedures

### Regular Maintenance Tasks

1. **Monitor Disk Space**
   ```bash
   # Check log directory
   du -sh /var/log/zabbix/
   
   # Check database size
   mysql -u zabbix -p -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'MB' FROM information_schema.tables WHERE table_schema='zabbix';"
   ```

2. **Update SSH Keys**
   ```bash
   # Backup current keys
   cp /home/zabbixssh/.ssh/authorized_keys /home/zabbixssh/.ssh/authorized_keys.bak.$(date +%Y%m%d)
   
   # Add new keys, remove old ones as needed
   ```

3. **Monitor Performance**
   ```bash
   # Check server performance
   zabbix_server -R config_cache_reload
   
   # Monitor database performance
   mysqladmin -u zabbix -p processlist
   ```

## Quick Reference

### Important Files and Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| SSH Config | `/etc/ssh/sshd_config` | SSH server configuration |
| Authorized Keys | `/home/zabbixssh/.ssh/authorized_keys` | Agent public keys |
| Zabbix Config | `/etc/zabbix/zabbix_server.conf` | Zabbix server settings |
| Zabbix Logs | `/var/log/zabbix/zabbix_server.log` | Server operation logs |
| SSH Logs | `/var/log/auth.log` | SSH connection logs |

### Essential Commands

```bash
# Restart services
sudo systemctl restart sshd zabbix-server

# Check service status
sudo systemctl status sshd zabbix-server

# Monitor connections
netstat -tlnp | grep -E ':(20202|10051)'

# Test agent connectivity
zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname

# View active tunnels
ps aux | grep "ssh.*zabbixssh"
```

---

**Note**: This configuration assumes the default settings from the Virtualizor server setup script. Adjust IP addresses, ports, and paths according to your specific environment.

For additional support, contact: support@everythingcloud.ca
