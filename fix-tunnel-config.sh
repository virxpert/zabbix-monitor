#!/bin/bash
# Quick fix for SSH tunnel configuration
# Run this on the server that has the wrong hostname

echo "🔧 Fixing SSH tunnel configuration..."

# Stop the current service
systemctl stop zabbix-tunnel 2>/dev/null || true

# Recreate the service file with correct parameters
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

# Reload systemd and enable the service
systemctl daemon-reload
systemctl enable zabbix-tunnel

echo "✅ SSH tunnel service updated"
echo "📋 Check configuration: systemctl cat zabbix-tunnel"
echo "🔄 Start tunnel: systemctl start zabbix-tunnel"
echo "📊 Check status: systemctl status zabbix-tunnel"
