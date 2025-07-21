# Homelab NAT Configuration for Zabbix Monitoring

This guide explains how to configure your homelab router and network for secure Zabbix monitoring using SSH tunnels without exposing monitoring ports to the internet.

## Network Architecture

```text
Internet → Router NAT → Homelab Zabbix Server → Agent Connections via SSH Tunnels

External Agents                Router/Firewall           Internal Zabbix Server
    |                              |                           |
    | SSH to port 20202            | NAT: 20202 → 22          | SSH daemon (port 22)
    |                              |                           | Zabbix server (port 10051)
    | Reverse tunnel               | Blocks 10050/10051       | Zabbix agent test (port 10050)
    | 10051:localhost:10051        | (security!)               |
```

## Router Configuration

### NAT/Port Forwarding Rule

Configure ONE port forwarding rule on your router:

```text
Rule Name: Zabbix SSH Tunnel
External Port: 20202
Internal IP: [your-zabbix-server-ip]
Internal Port: 22
Protocol: TCP
Description: SSH tunnels for Zabbix monitoring
```

### Example Router Configurations

#### pfSense/OPNsense
```text
Firewall → NAT → Port Forward → Add
Interface: WAN
Protocol: TCP
External Port: 20202
Internal IP: 192.168.1.100 (your Zabbix server)
Internal Port: 22
```

#### Ubiquiti UniFi
```text
Settings → Routing & Firewall → Port Forwarding
Name: Zabbix SSH
From: Any
Port: 20202
Forward IP: 192.168.1.100
Forward Port: 22
Protocol: TCP
```

#### Generic Home Router
```text
Advanced → NAT/Gaming → Port Forwarding
Service Name: Zabbix SSH
External Port: 20202
Internal IP: 192.168.1.100
Internal Port: 22
Protocol: TCP
```

### Firewall Rules (If Applicable)

Most routers automatically create firewall rules for port forwards, but if needed:

```text
Action: Allow
Source: Any
Destination: Router IP
Port: 20202
Protocol: TCP
```

## Internal Server Configuration

### Network Information You'll Need

Before configuring, gather this information:

```bash
# Find your internal Zabbix server IP
ip addr show
# or
hostname -I

# Verify SSH is running on port 22
sudo netstat -tlnp | grep :22

# Test internal connectivity
ping 127.0.0.1
```

### Firewall Configuration on Zabbix Server

```bash
# Configure UFW for secure internal access
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (for tunnels)
sudo ufw allow 22/tcp

# Allow Zabbix ports for localhost only (tunnel endpoints)
sudo ufw allow from 127.0.0.1 to any port 10050 comment "Zabbix agent (tunnel)"
sudo ufw allow from 127.0.0.1 to any port 10051 comment "Zabbix server (tunnel)"

# Allow from internal network if needed (optional)
sudo ufw allow from 192.168.1.0/24 to any port 22 comment "SSH from LAN"
sudo ufw allow from 192.168.1.0/24 to any port 10050 comment "Zabbix agent from LAN"

# Enable firewall
sudo ufw --force enable
sudo ufw status verbose
```

### Verify SSH Configuration

```bash
# Check SSH is configured correctly
sudo sshd -t

# Verify SSH is listening on port 22
sudo ss -tlnp | grep :22

# Test SSH from internal network
ssh username@localhost

# Check SSH configuration
grep -E "^(Port|AllowUsers|AllowTcpForwarding)" /etc/ssh/sshd_config
```

## Testing the NAT Configuration

### From Outside Your Network

```bash
# Test external SSH access (from internet)
ssh -p 20202 zabbixssh@monitor.cloudgeeks.in

# If this works, your NAT is configured correctly
```

### From Inside Your Network

```bash
# Test internal SSH access
ssh zabbixssh@192.168.1.100  # Your internal IP

# Test tunnel creation manually
ssh -N -R 10051:localhost:10051 zabbixssh@192.168.1.100
```

## DNS Configuration

### Domain Setup

Your domain `monitor.cloudgeeks.in` should point to your public IP:

```bash
# Check DNS resolution
nslookup monitor.cloudgeeks.in
dig monitor.cloudgeeks.in

# Should return your public IP address
```

### Dynamic DNS (If Needed)

If your ISP changes your IP address frequently:

```bash
# Common Dynamic DNS providers:
# - DuckDNS
# - No-IP
# - DynDNS
# - Cloudflare (with API updates)

# Example with DuckDNS (runs on your router or server)
curl "https://www.duckdns.org/update?domains=yourdomain&token=yourtoken&ip="
```

## Security Considerations

### What Gets Exposed vs Protected

**Exposed to Internet:**
- ✅ Port 20202 (SSH only) - secured by SSH key authentication
- ✅ SSH daemon with restricted `zabbixssh` user

**Protected from Internet:**
- 🔒 Port 10050 (Zabbix agent) - never exposed
- 🔒 Port 10051 (Zabbix server) - never exposed  
- 🔒 All Zabbix communication flows through encrypted SSH tunnels
- 🔒 No direct access to Zabbix services

### Additional Security Measures

```bash
# 1. Restrict SSH access by IP (if you have static IPs for agents)
# In /etc/ssh/sshd_config:
# Match User zabbixssh
#     AllowUsers zabbixssh@203.0.113.10
#     AllowUsers zabbixssh@203.0.113.20

# 2. Use fail2ban for SSH protection
sudo apt install fail2ban
sudo systemctl enable fail2ban

# 3. Monitor SSH connections
sudo tail -f /var/log/auth.log | grep sshd

# 4. Regular security updates
sudo apt update && sudo apt upgrade
```

## Troubleshooting NAT Issues

### Common Problems

#### "Connection Refused" from Internet

```bash
# Check if port is forwarded correctly
# From outside your network:
telnet monitor.cloudgeeks.in 20202

# Should connect to SSH
```

**Solutions:**
1. Verify NAT rule is enabled
2. Check router firewall isn't blocking
3. Confirm internal SSH is running on port 22
4. Verify internal server IP hasn't changed

#### "Connection Times Out"

**Possible causes:**
1. ISP blocking port 20202
2. Router firewall blocking
3. Internal server firewall blocking
4. Internal SSH service not running

```bash
# Test from inside network first
ssh -p 22 zabbixssh@192.168.1.100

# If internal works but external doesn't, it's a router/firewall issue
```

#### Multiple SSH Services

```bash
# If you run SSH on a non-standard port internally:
# 1. Change your internal SSH port
sudo nano /etc/ssh/sshd_config
# Port 2222

# 2. Update NAT rule
# External: 20202 → Internal: 2222

# 3. Update firewall
sudo ufw allow 2222/tcp
```

### Debug Commands

```bash
# On router (if accessible):
# Check NAT table
iptables -t nat -L PREROUTING -n -v

# On internal server:
# Check connections
sudo netstat -anp | grep :22 | grep ESTABLISHED

# Monitor connection attempts
sudo journalctl -u sshd -f

# Test local Zabbix connectivity
zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname
```

## Network Topology Examples

### Simple Home Network

```text
Internet
   |
 Router (192.168.1.1)
   |
   +-- Zabbix Server (192.168.1.100:22)
   +-- Other devices (192.168.1.x)

NAT Rule: 20202 → 192.168.1.100:22
```

### Complex Network with VLANs

```text
Internet
   |
 Router/Firewall
   |
   +-- Management VLAN (10.0.1.0/24)
   |   +-- Zabbix Server (10.0.1.100:22)
   |
   +-- User VLAN (10.0.2.0/24)
   +-- Guest VLAN (10.0.3.0/24)

NAT Rule: 20202 → 10.0.1.100:22
Firewall: Allow inter-VLAN for monitoring
```

### DMZ Setup

```text
Internet
   |
 Router/Firewall
   |
   +-- DMZ (10.0.0.0/24)
   |   +-- Zabbix Server (10.0.0.100:22)
   |
   +-- Internal Network (192.168.1.0/24)

NAT Rule: 20202 → 10.0.0.100:22
DMZ Rules: Allow inbound 20202, block everything else
```

## Monitoring and Maintenance

### Regular Checks

```bash
#!/bin/bash
# /usr/local/bin/nat-health-check.sh

echo "=== NAT Health Check ==="
echo "Date: $(date)"
echo ""

# Check external connectivity
if timeout 5 ssh -o ConnectTimeout=5 -o BatchMode=yes -p 20202 zabbixssh@monitor.cloudgeeks.in exit 2>/dev/null; then
    echo "✅ External SSH access: OK"
else
    echo "❌ External SSH access: FAILED"
fi

# Check internal SSH
if timeout 5 ssh -o ConnectTimeout=5 -o BatchMode=yes zabbixssh@localhost exit 2>/dev/null; then
    echo "✅ Internal SSH access: OK"  
else
    echo "❌ Internal SSH access: FAILED"
fi

# Check active tunnels
tunnel_count=$(netstat -tlnp 2>/dev/null | grep ":10051 " | wc -l)
echo "📊 Active tunnels: $tunnel_count"

# Check Zabbix services
systemctl is-active zabbix-server >/dev/null && echo "✅ Zabbix server: Running" || echo "❌ Zabbix server: Stopped"
```

### Log Monitoring

```bash
# Monitor SSH connections
sudo tail -f /var/log/auth.log | grep "Accepted\|Failed"

# Monitor Zabbix server
sudo tail -f /var/log/zabbix/zabbix_server.log

# Monitor tunnel establishment
sudo journalctl -f -u ssh -t sshd
```

## Backup and Recovery

### Configuration Backup

```bash
#!/bin/bash
# Backup critical configuration files
backup_dir="/home/admin/config-backup-$(date +%Y%m%d)"
mkdir -p "$backup_dir"

# SSH configuration
sudo cp /etc/ssh/sshd_config "$backup_dir/"

# Zabbix configuration
sudo cp /etc/zabbix/zabbix_server.conf "$backup_dir/"

# Authorized keys
sudo cp /home/zabbixssh/.ssh/authorized_keys "$backup_dir/"

# Firewall rules
sudo ufw status verbose > "$backup_dir/ufw-rules.txt"

echo "Configuration backed up to: $backup_dir"
```

### Disaster Recovery

```bash
# If NAT stops working:
# 1. Check router status
# 2. Verify internal SSH service
# 3. Confirm firewall rules
# 4. Test internal connectivity first
# 5. Check DNS resolution

# Emergency SSH access via internal network:
ssh admin@192.168.1.100  # Use your actual internal IP
```

---

**Key Points:**
- Only one port (20202) needs to be forwarded on your router
- Zabbix ports (10050/10051) stay internal and secure
- All monitoring traffic flows through encrypted SSH tunnels
- Regular monitoring ensures continued operation
