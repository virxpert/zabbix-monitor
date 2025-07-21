# Virtualizor Configuration Guide

## 🔧 Dynamic Configuration for Zabbix Monitor Scripts

This guide explains how to configure the Zabbix monitoring scripts for different Virtualizor deployment scenarios.

## 🔒 Security First

**⚠️ CRITICAL SECURITY REQUIREMENTS:**

1. **Never use example/default values in production**
2. **Always use unique ports (avoid 22, 2222, 20202)**
3. **Use unpredictable usernames (avoid 'zabbix', 'zabbixssh')**
4. **Protect configuration from unauthorized access**

## 📋 Configuration Methods

### **Method 1: Environment Variables (Recommended)**

Best for automated deployments and CI/CD integration:

```bash
# Set environment variables before script execution
export ZABBIX_SERVER_DOMAIN="monitoring.yourcompany.com"
export SSH_TUNNEL_PORT="2022"
export SSH_TUNNEL_USER="zbx-monitor"
export ZABBIX_VERSION="6.4"
export ZABBIX_SERVER_PORT="10051"

# Execute script with environment
curl -fsSL https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh | bash
```

### **Method 2: Command-Line Parameters**

Best for direct script execution:

```bash
wget -O /tmp/setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
chmod +x /tmp/setup.sh

./setup.sh \
    --ssh-host "monitoring.yourcompany.com" \
    --ssh-port "2022" \
    --ssh-user "zbx-monitor" \
    --zabbix-version "6.4" \
    --zabbix-server-port "10051"
```

### **Method 3: Recipe Configuration**

Best for Virtualizor recipe deployment:

1. **Edit Recipe File**: Modify the configuration section in your chosen recipe
2. **Update Values**: Replace example values with your actual configuration
3. **Deploy Recipe**: Use the updated recipe in Virtualizor

## 🎯 Virtualizor Recipe Deployment

### **Option A: Direct Download Recipe (Simplest)**

```bash
# 1. Download and customize the recipe
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh

# 2. Edit the configuration section
nano direct-download-recipe.sh

# 3. Update these lines with YOUR values:
export ZABBIX_SERVER_DOMAIN="your-actual-server.com"    # ⚠️ CHANGE THIS
export SSH_TUNNEL_PORT="your-unique-port"               # ⚠️ CHANGE THIS  
export SSH_TUNNEL_USER="your-unique-username"           # ⚠️ CHANGE THIS

# 4. Deploy in Virtualizor as post-installation script
```

### **Option B: Embedded Script Recipe (Offline-Ready)**

```bash
# 1. Download the embedded recipe
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/embedded-script-recipe.sh

# 2. Customize configuration section
# 3. Deploy in Virtualizor - works even without internet during provisioning
```

### **Option C: Cloud-Init Compatible**

```bash
# 1. Use for cloud-init or systemd-based deployments  
# 2. Supports multi-boot scenarios and complex provisioning
```

## 🔧 Configuration Parameters

### **Required Parameters**

| Parameter | Environment Variable | CLI Parameter | Description |
|-----------|---------------------|---------------|-------------|
| Monitoring Server | `ZABBIX_SERVER_DOMAIN` | `--ssh-host` | Your Zabbix monitoring server FQDN/IP |
| SSH Port | `SSH_TUNNEL_PORT` | `--ssh-port` | SSH tunnel port (use non-standard) |
| SSH User | `SSH_TUNNEL_USER` | `--ssh-user` | SSH tunnel username (use unique name) |

### **Optional Parameters**

| Parameter | Environment Variable | CLI Parameter | Default | Description |
|-----------|---------------------|---------------|---------|-------------|
| Zabbix Version | `ZABBIX_VERSION` | `--zabbix-version` | `6.4` | Zabbix agent version |
| Zabbix Port | `ZABBIX_SERVER_PORT` | `--zabbix-server-port` | `10051` | Zabbix server port |

## 💡 Best Practices

### **Security Configuration**

```bash
# ✅ GOOD Examples:
ZABBIX_SERVER_DOMAIN="monitor.internal.mycompany.com"
SSH_TUNNEL_PORT="2847"         # Unique, non-standard port
SSH_TUNNEL_USER="zbx-tun-usr"  # Unique, unpredictable username

# ❌ BAD Examples (Never use these):
ZABBIX_SERVER_DOMAIN="monitor.cloudgeeks.in"  # Example domain
SSH_TUNNEL_PORT="22"                           # Standard SSH port  
SSH_TUNNEL_USER="zabbix"                       # Predictable username
```

### **Network Configuration**

```bash
# Ensure your monitoring server is accessible:
# - Firewall allows SSH on your chosen port
# - Monitoring server accepts connections from new servers
# - DNS resolution works for your domain
```

### **Virtualizor Recipe Testing**

```bash
# Test your recipe configuration:
# 1. Deploy on test VM first
# 2. Check logs: /var/log/zabbix-scripts/virtualizor-server-setup-*.log
# 3. Verify SSH tunnel: ss -tlnp | grep YOUR_PORT
# 4. Test Zabbix connectivity: zabbix_get -s localhost -k system.hostname
```

## 🚨 Troubleshooting

### **Configuration Validation Errors**

```bash
# Error: "Using example domain"
# Fix: Update ZABBIX_SERVER_DOMAIN with your actual server

# Error: "Using common SSH port"  
# Fix: Choose unique port (e.g., 2000-9000 range, avoid common ports)

# Error: "Using predictable username"
# Fix: Use unique username (e.g., zbx-mon-user, not zabbix)
```

### **Runtime Issues**

```bash
# Check configuration values:
echo "Server: $ZABBIX_SERVER_DOMAIN"
echo "Port: $SSH_TUNNEL_PORT"  
echo "User: $SSH_TUNNEL_USER"

# Check script logs:
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Test connectivity:
telnet $ZABBIX_SERVER_DOMAIN $SSH_TUNNEL_PORT
```

## 📝 Example Configurations

### **Small Business Setup**

```bash
export ZABBIX_SERVER_DOMAIN="monitor.mybusiness.local"
export SSH_TUNNEL_PORT="2150"
export SSH_TUNNEL_USER="mon-agent"
export ZABBIX_VERSION="6.4"
```

### **Enterprise Setup**

```bash
export ZABBIX_SERVER_DOMAIN="zabbix-prod.enterprise.internal"
export SSH_TUNNEL_PORT="3842"
export SSH_TUNNEL_USER="zbx-tunnel-svc"
export ZABBIX_VERSION="6.4"
export ZABBIX_SERVER_PORT="10051"
```

### **Multi-Environment Setup**

```bash
# Production
export ZABBIX_SERVER_DOMAIN="zabbix-prod.company.com"
export SSH_TUNNEL_PORT="2800"
export SSH_TUNNEL_USER="prod-zbx-agent"

# Staging  
export ZABBIX_SERVER_DOMAIN="zabbix-stage.company.com"
export SSH_TUNNEL_PORT="2801"
export SSH_TUNNEL_USER="stage-zbx-agent"
```

## 🔄 Configuration Updates

To update configuration for existing deployments:

```bash
# 1. Update environment variables
export ZABBIX_SERVER_DOMAIN="new-monitor-server.com"
export SSH_TUNNEL_PORT="3333"

# 2. Re-run configuration stage
./virtualizor-server-setup.sh --stage zabbix-configure

# 3. Or run specific configuration update
systemctl restart zabbix-agent
```

---

**Need Help?** Check the [troubleshooting guide](troubleshooting-guide.md) or review the [main documentation](../README.md).
