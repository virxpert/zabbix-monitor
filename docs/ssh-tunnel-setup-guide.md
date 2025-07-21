# SSH Tunnel Setup - Quick Reference Guide

This guide provides the essential steps for configuring SSH tunnels between Zabbix agents and the monitoring server.

## Prerequisites

- Zabbix server running in homelab behind NAT router
- Domain/IP: `monitor.cloudgeeks.in` (points to your public IP)
- NAT rule: External port 20202 → Internal SSH port 22
- SSH access to the Zabbix server with sudo privileges
- Agent servers provisioned with the Virtualizor setup script

**Network Setup:**
- Router NAT: `20202 (external) → 22 (internal Zabbix server)`
- Zabbix ports (10050/10051) stay internal - **NO router port forwarding needed**
- SSH tunnels handle all Zabbix traffic securely

## Server Setup (One-time Configuration)

### 1. Create SSH Tunnel User

```bash
# On monitor.cloudgeeks.in
sudo useradd -m -s /bin/bash zabbixssh
sudo mkdir -p /home/zabbixssh/.ssh
sudo chmod 700 /home/zabbixssh/.ssh
sudo touch /home/zabbixssh/.ssh/authorized_keys
sudo chmod 600 /home/zabbixssh/.ssh/authorized_keys
sudo chown -R zabbixssh:zabbixssh /home/zabbixssh/.ssh
```

### 2. Configure SSH Service

**Important**: Since you're using NAT (20202 → 22), configure SSH on the **internal** server to use the standard port 22.

Edit `/etc/ssh/sshd_config` on your homelab Zabbix server:

```bash
# Keep standard SSH port (22) - NAT handles external port 20202
Port 22

# Allow the tunnel user
AllowUsers root zabbixssh

# Enable tunneling
AllowTcpForwarding yes
GatewayPorts yes

# Restrict tunnel user to only tunneling
Match User zabbixssh
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

### 3. Configure Firewall (Internal Server Only)

**Note**: Only configure firewall on your internal Zabbix server. No router port forwarding needed for Zabbix ports.

```bash
# On the internal Zabbix server - allow SSH locally
sudo ufw allow 22/tcp

# Allow Zabbix ports for internal connections only (tunnels will use these)
sudo ufw allow from 127.0.0.1 to any port 10050
sudo ufw allow from 127.0.0.1 to any port 10051

# Reload firewall
sudo ufw reload
```

**Router Configuration** (one-time setup):
- NAT Rule: External port `20202` → Internal IP:port `[zabbix-server-ip]:22`
- **Do NOT** forward ports 10050 or 10051 - security risk!
- SSH tunnels will handle all Zabbix traffic securely

## Per-Agent Configuration

### 1. Run Virtualizor Setup Script

On each agent server:

```bash
./virtualizor-server-setup.sh
```

### 2. Collect SSH Public Key

The script will generate an SSH key and display the public key:

```text
[WARN] MANUAL ACTION REQUIRED:
[WARN] Copy the following public key to the remote server:
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...xyz zabbix-tunnel-hostname-20250721
```

### 3. Add Public Key to Server

On `monitor.cloudgeeks.in`:

```bash
sudo nano /home/zabbixssh/.ssh/authorized_keys
```

Add the public key on a new line, then save and exit.

### 4. Start Tunnel Service

On the agent server:

```bash
sudo systemctl start zabbix-tunnel
sudo systemctl status zabbix-tunnel
```

### 5. Add Host in Zabbix Web Interface

1. Login to Zabbix: `http://monitor.cloudgeeks.in/zabbix`
2. Go to Configuration → Hosts
3. Click "Create host"
4. Configure:
   - **Host name**: `server-hostname`
   - **Groups**: `Virtualizor Servers`
   - **Interface**: Agent, IP: `127.0.0.1`, Port: `10050`
   - **Templates**: `Linux by Zabbix agent`

## Verification Commands

### On Zabbix Server (Homelab)

```bash
# Check active tunnels (should show connections from remote agents)
netstat -tlnp | grep :10051

# Test agent connectivity through tunnel
zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname

# Monitor Zabbix server logs
tail -f /var/log/zabbix/zabbix_server.log

# Check SSH connections from agents
sudo netstat -anp | grep :22 | grep ESTABLISHED
```

### On Agent Server

```bash
# Check tunnel status
systemctl status zabbix-tunnel

# Check Zabbix agent status
systemctl status zabbix-agent

# Test SSH connection
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Quick status check
./virtualizor-server-setup.sh --quick-status
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| SSH connection refused | Check firewall, SSH service, port configuration |
| Tunnel won't start | Verify SSH key is added to authorized_keys |
| Zabbix shows agent unavailable | Check tunnel status, verify host configuration |
| Permission denied | Check SSH key permissions (600) and ownership |

### Debug Commands

```bash
# Detailed SSH connection test
ssh -vvv -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Check tunnel service logs
journalctl -u zabbix-tunnel -f

# Monitor Zabbix server logs
journalctl -u zabbix-server -f

# Comprehensive system validation
./virtualizor-server-setup.sh --validate
```

## Security Notes

- SSH keys are generated without passphrases for automated operation
- The `zabbixssh` user is restricted to tunneling only (ForceCommand /bin/false)
- Use StrictHostKeyChecking=no for automated connections
- **NAT-based security**: Zabbix ports (10050/10051) never exposed to internet
- Only SSH port accessible through router NAT (20202 → 22)
- All Zabbix traffic flows through encrypted SSH tunnels
- Consider additional VPN layer for enhanced security

## Support

For technical issues contact: support@everythingcloud.ca

---

**Quick Setup Checklist:**

- [ ] Create `zabbixssh` user on homelab Zabbix server
- [ ] Configure SSH service (standard port 22, allow tunneling)
- [ ] Configure router NAT rule (20202 → internal-server:22)
- [ ] Configure internal server firewall (allow SSH and local Zabbix ports)
- [ ] **Do NOT forward Zabbix ports 10050/10051 on router**
- [ ] Run setup script on agent server
- [ ] Copy public key to server's authorized_keys
- [ ] Start tunnel service
- [ ] Add host in Zabbix web interface (IP: 127.0.0.1)
- [ ] Verify connectivity through tunnel
