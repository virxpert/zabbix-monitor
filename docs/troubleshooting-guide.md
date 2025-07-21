# SSH Tunnel Troubleshooting Guide

This guide helps diagnose and resolve common issues with SSH tunnels between Zabbix agents and the monitoring server.

## Common Issues and Solutions

### 1. SSH Connection Refused

**Symptoms:**
- `Connection refused` error in tunnel logs
- Tunnel service fails to start
- Agent appears offline in Zabbix

**Diagnostic Commands:**
```bash
# On agent server - test basic SSH connectivity
ssh -p 20202 zabbixssh@monitor.cloudgeeks.in

# Check if SSH port is open
telnet monitor.cloudgeeks.in 20202
nc -zv monitor.cloudgeeks.in 20202
```

**Solutions:**

1. **Check SSH Service on Server:**
   ```bash
   # On monitor.cloudgeeks.in
   sudo systemctl status sshd
   sudo systemctl restart sshd
   ```

2. **Verify SSH Configuration:**
   ```bash
   # Check SSH config syntax
   sudo sshd -t
   
   # Check if custom port is configured
   sudo grep -E "^Port" /etc/ssh/sshd_config
   ```

3. **Check Firewall:**
   ```bash
   # On monitor.cloudgeeks.in
   sudo ufw status
   sudo ufw allow 20202/tcp
   ```

### 2. Authentication Failures

**Symptoms:**
- `Permission denied (publickey)` error
- SSH key authentication fails
- Tunnel connects briefly then disconnects

**Diagnostic Commands:**
```bash
# Test SSH with verbose output
ssh -vvv -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Check SSH key permissions
ls -la /root/.ssh/zabbix_tunnel_key*
```

**Solutions:**

1. **Fix SSH Key Permissions:**
   ```bash
   # On agent server
   chmod 600 /root/.ssh/zabbix_tunnel_key
   chmod 644 /root/.ssh/zabbix_tunnel_key.pub
   ```

2. **Verify Public Key on Server:**
   ```bash
   # On monitor.cloudgeeks.in
   sudo cat /home/zabbixssh/.ssh/authorized_keys
   sudo chmod 600 /home/zabbixssh/.ssh/authorized_keys
   sudo chown zabbixssh:zabbixssh /home/zabbixssh/.ssh/authorized_keys
   ```

3. **Check SSH User Configuration:**
   ```bash
   # Verify zabbixssh user exists
   id zabbixssh
   
   # Check home directory permissions
   ls -la /home/zabbixssh/
   ```

### 3. Tunnel Service Issues

**Symptoms:**
- `systemctl status zabbix-tunnel` shows failed/inactive
- Service starts but tunnel doesn't establish
- Frequent service restarts

**Diagnostic Commands:**
```bash
# Check service status and logs
systemctl status zabbix-tunnel
journalctl -u zabbix-tunnel -f
journalctl -u zabbix-tunnel --since "1 hour ago"
```

**Solutions:**

1. **Manual Tunnel Test:**
   ```bash
   # Test tunnel creation manually
   ssh -i /root/.ssh/zabbix_tunnel_key \
       -o ExitOnForwardFailure=yes \
       -o ServerAliveInterval=60 \
       -o ServerAliveCountMax=3 \
       -o StrictHostKeyChecking=no \
       -o BatchMode=yes \
       -N -R 10051:localhost:10051 \
       -p 20202 \
       zabbixssh@monitor.cloudgeeks.in
   ```

2. **Check Network Connectivity:**
   ```bash
   # Test network path to server
   traceroute monitor.cloudgeeks.in
   ping -c 4 monitor.cloudgeeks.in
   
   # Test specific port connectivity
   telnet monitor.cloudgeeks.in 20202
   ```

3. **Restart Services in Order:**
   ```bash
   systemctl stop zabbix-tunnel
   systemctl stop zabbix-agent
   sleep 5
   systemctl start zabbix-agent
   systemctl start zabbix-tunnel
   ```

### 4. Zabbix Agent Not Responding

**Symptoms:**
- Tunnel is active but agent shows unavailable
- Zabbix server can't connect to agent
- Agent appears red/unreachable in web interface

**Diagnostic Commands:**
```bash
# Check if agent is listening
netstat -tlnp | grep :10050
ss -tlnp | grep :10050

# Test agent locally
zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname

# Check agent status
systemctl status zabbix-agent
```

**Solutions:**

1. **Verify Agent Configuration:**
   ```bash
   # Check agent config
   grep -E "^(Server|ServerActive|Hostname)" /etc/zabbix/zabbix_agentd.conf
   
   # Should show:
   # Server=127.0.0.1
   # ServerActive=127.0.0.1
   # Hostname=your-hostname
   ```

2. **Restart Agent Service:**
   ```bash
   systemctl restart zabbix-agent
   systemctl enable zabbix-agent
   ```

3. **Check Agent Logs:**
   ```bash
   tail -f /var/log/zabbix/zabbix_agentd.log
   journalctl -u zabbix-agent -f
   ```

### 5. Port Conflicts

**Symptoms:**
- "Address already in use" errors
- Tunnel service fails to bind to port
- Multiple tunnel services running

**Diagnostic Commands:**
```bash
# Check what's using port 10051
lsof -i :10051
netstat -tlnp | grep :10051

# Check for multiple tunnel processes
ps aux | grep zabbix-tunnel
ps aux | grep "ssh.*10051"
```

**Solutions:**

1. **Kill Conflicting Processes:**
   ```bash
   # Stop all tunnel services
   systemctl stop zabbix-tunnel
   
   # Kill any remaining SSH tunnels
   pkill -f "ssh.*10051"
   
   # Restart clean
   systemctl start zabbix-tunnel
   ```

2. **Check Service Configuration:**
   ```bash
   # Verify service file
   systemctl cat zabbix-tunnel
   
   # Look for port conflicts in systemd
   systemctl list-units | grep tunnel
   ```

### 6. Host Configuration Issues

**Symptoms:**
- Host exists in Zabbix but shows as unavailable
- Data collection not working
- Interface errors in Zabbix logs

**Solutions:**

1. **Verify Host Configuration in Zabbix:**
   - Interface IP: `127.0.0.1`
   - Interface Port: `10050`
   - Interface Type: `Zabbix agent`

2. **Check from Zabbix Server:**
   ```bash
   # On monitor.cloudgeeks.in
   zabbix_get -s 127.0.0.1 -p 10050 -k system.hostname
   
   # Check server logs
   tail -f /var/log/zabbix/zabbix_server.log | grep hostname
   ```

## Diagnostic Scripts

### Complete System Check

```bash
#!/bin/bash
# comprehensive-check.sh - Run on agent server

echo "=== Zabbix Tunnel Diagnostic Check ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

echo "1. SSH Key Status:"
if [ -f "/root/.ssh/zabbix_tunnel_key" ]; then
    echo "✓ SSH key exists"
    ls -la /root/.ssh/zabbix_tunnel_key*
else
    echo "✗ SSH key missing"
fi
echo ""

echo "2. Service Status:"
systemctl is-active zabbix-agent && echo "✓ Zabbix Agent: Running" || echo "✗ Zabbix Agent: Stopped"
systemctl is-active zabbix-tunnel && echo "✓ Tunnel Service: Running" || echo "✗ Tunnel Service: Stopped"
echo ""

echo "3. Network Connectivity:"
if ping -c 1 monitor.cloudgeeks.in >/dev/null 2>&1; then
    echo "✓ Server reachable"
else
    echo "✗ Server unreachable"
fi

if nc -zv monitor.cloudgeeks.in 20202 2>/dev/null; then
    echo "✓ SSH port accessible"
else
    echo "✗ SSH port blocked"
fi
echo ""

echo "4. Local Services:"
if netstat -tlnp 2>/dev/null | grep -q ":10050.*zabbix_agentd"; then
    echo "✓ Zabbix agent listening on 10050"
else
    echo "✗ Zabbix agent not listening"
fi
echo ""

echo "5. Tunnel Connection:"
tunnel_pid=$(systemctl show zabbix-tunnel --property MainPID --value 2>/dev/null)
if [ -n "$tunnel_pid" ] && [ "$tunnel_pid" != "0" ]; then
    echo "✓ Tunnel active (PID: $tunnel_pid)"
else
    echo "✗ No active tunnel"
fi
echo ""

echo "6. Configuration Check:"
if grep -q "^Server=127.0.0.1" /etc/zabbix/zabbix_agentd.conf; then
    echo "✓ Agent configured for tunnel"
else
    echo "✗ Agent not configured for tunnel"
fi
```

### Server-Side Check

```bash
#!/bin/bash
# server-check.sh - Run on monitor.cloudgeeks.in

echo "=== Zabbix Server Tunnel Check ==="
echo "Date: $(date)"
echo ""

echo "1. SSH Service:"
systemctl is-active sshd && echo "✓ SSH service running" || echo "✗ SSH service stopped"
if netstat -tlnp | grep -q ":20202"; then
    echo "✓ SSH listening on port 20202"
else
    echo "✗ SSH not listening on 20202"
fi
echo ""

echo "2. Tunnel User:"
if id zabbixssh >/dev/null 2>&1; then
    echo "✓ zabbixssh user exists"
    if [ -f "/home/zabbixssh/.ssh/authorized_keys" ]; then
        key_count=$(wc -l < /home/zabbixssh/.ssh/authorized_keys)
        echo "✓ Authorized keys file exists ($key_count keys)"
    else
        echo "✗ No authorized_keys file"
    fi
else
    echo "✗ zabbixssh user missing"
fi
echo ""

echo "3. Active Tunnels:"
tunnel_count=$(netstat -tlnp 2>/dev/null | grep ":10051 " | wc -l)
if [ $tunnel_count -gt 0 ]; then
    echo "✓ $tunnel_count active tunnel(s)"
    netstat -tlnp | grep ":10051"
else
    echo "✗ No active tunnels"
fi
echo ""

echo "4. Zabbix Server:"
systemctl is-active zabbix-server && echo "✓ Zabbix server running" || echo "✗ Zabbix server stopped"
if netstat -tlnp | grep -q ":10051.*zabbix_server"; then
    echo "✓ Zabbix server listening"
else
    echo "✗ Zabbix server not listening"
fi
```

## Emergency Recovery Procedures

### Complete Reset (Agent Side)

```bash
# Stop all services
systemctl stop zabbix-tunnel zabbix-agent

# Clean up
rm -f /var/run/virtualizor-server-setup.*
rm -f /root/.ssh/zabbix_tunnel_key*

# Restart setup from tunnel stage
./virtualizor-server-setup.sh --stage tunnel-setup
```

### Complete Reset (Server Side)

```bash
# Stop services
systemctl stop zabbix-server

# Clear authorized keys
> /home/zabbixssh/.ssh/authorized_keys

# Restart services
systemctl restart sshd zabbix-server
```

## Monitoring and Alerting

### Log Monitoring

```bash
# Monitor all tunnel-related logs
tail -f /var/log/zabbix/zabbix_agentd.log \
        /var/log/auth.log \
        <(journalctl -u zabbix-tunnel -f) \
        <(journalctl -u zabbix-agent -f)
```

### Automated Health Check

Create `/usr/local/bin/tunnel-health-check.sh`:

```bash
#!/bin/bash
# Automated health check for Zabbix tunnels

LOGFILE="/var/log/tunnel-health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

check_status() {
    if systemctl is-active zabbix-tunnel >/dev/null 2>&1 && \
       systemctl is-active zabbix-agent >/dev/null 2>&1 && \
       netstat -tlnp | grep -q ":10050.*zabbix_agentd"; then
        echo "[$DATE] OK: All services healthy" >> $LOGFILE
        return 0
    else
        echo "[$DATE] ERROR: Service health check failed" >> $LOGFILE
        # Restart services
        systemctl restart zabbix-agent zabbix-tunnel
        return 1
    fi
}

# Run check
check_status
```

Add to crontab:
```bash
# Check every 5 minutes
*/5 * * * * /usr/local/bin/tunnel-health-check.sh
```

## Contact Information

For persistent issues or additional support:

- **Technical Support**: support@everythingcloud.ca
- **Emergency Issues**: Check server logs and contact immediately
- **Documentation Updates**: Submit issues to repository

---

**Remember**: Always check the basics first - network connectivity, service status, and configuration files before diving into complex troubleshooting.
