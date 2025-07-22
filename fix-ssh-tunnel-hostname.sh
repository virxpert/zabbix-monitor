#!/bin/bash
# Quick fix for SSH tunnel configuration on existing server
# This fixes the hostname issue without re-running the entire setup

echo "🔧 Fixing SSH tunnel configuration on $(hostname)..."
echo "📅 $(date)"

# Stop the current broken service
echo "🛑 Stopping current tunnel service..."
systemctl stop zabbix-tunnel 2>/dev/null || true

# Show what we're changing from
echo "📋 Current broken configuration:"
if [ -f /etc/systemd/system/zabbix-tunnel.service ]; then
    grep "ExecStart.*ssh" /etc/systemd/system/zabbix-tunnel.service | head -1
else
    echo "   Service file not found"
fi

# Create the corrected service file
echo "🔄 Creating corrected service configuration..."
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
    -p 22 \
    zabbixuser@monitor.somehost.com
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd configuration
echo "🔄 Reloading systemd configuration..."
systemctl daemon-reload

# Enable the service
systemctl enable zabbix-tunnel

# Show the new configuration
echo "✅ New configuration created:"
grep "ExecStart.*ssh" /etc/systemd/system/zabbix-tunnel.service | head -1

echo ""
echo "🔑 SSH Key Status:"
if [ -f /root/.ssh/zabbix_tunnel_key.pub ]; then
    echo "   ✅ SSH public key exists: /root/.ssh/zabbix_tunnel_key.pub"
    echo "   📋 Key fingerprint: $(ssh-keygen -lf /root/.ssh/zabbix_tunnel_key.pub 2>/dev/null | awk '{print $2}' || echo 'Unable to get fingerprint')"
else
    echo "   ❌ SSH key not found - tunnel will fail until key is configured"
fi

echo ""
echo "📊 Next Steps:"
echo "   1. Add SSH public key to monitor.somehost.com (see below)"
echo "   2. Start tunnel: systemctl start zabbix-tunnel"
echo "   3. Check status: systemctl status zabbix-tunnel"
echo "   4. View logs: journalctl -u zabbix-tunnel -f"

echo ""
echo "🔑 SSH Public Key to add to monitor.somehost.com:"
echo "   ➡️  Add this to zabbixuser@monitor.somehost.com:~/.ssh/authorized_keys"
if [ -f /root/.ssh/zabbix_tunnel_key.pub ]; then
    echo "   =================================================="
    cat /root/.ssh/zabbix_tunnel_key.pub
    echo "   =================================================="
else
    echo "   ❌ Public key file not found!"
fi

echo ""
echo "✅ SSH tunnel configuration fixed!"
echo "🎯 Now connecting to: zabbixuser@monitor.somehost.com:22"
