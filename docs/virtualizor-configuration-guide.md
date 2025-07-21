# Virtualizor Configuration Guide

## � Runtime Configuration Injection for Zabbix Monitor Scripts

This guide explains how to configure Zabbix monitoring scripts for Virtualizor automated provisioning using **runtime configuration injection** - the solution for configuring servers that don't exist yet.

## 💡 The Runtime Configuration Solution

**Traditional Problem**: You can't pre-configure servers before they're provisioned.

**✅ Our Solution**: Runtime configuration injection:
1. **Download**: Recipe downloads the latest script during provisioning
2. **Inject**: Recipe modifies the script with your configuration values using `sed`
3. **Execute**: Configured script runs automatically with your settings

## 🔒 Security First - Administrator Trust Model

**⚠️ CRITICAL SECURITY PRINCIPLE:**

1. **Administrator Responsibility**: System administrators are trusted to configure appropriate security settings
2. **Minimal Validation**: Only prevents deployment with placeholder example domain
3. **Clean Configuration**: No multiple fallback options that could create security vulnerabilities
4. **Single Configuration Path**: One clear configuration method to prevent confusion

## 📋 Configuration Methods

### **Method 1: Virtualizor Recipe with Runtime Injection** ⭐ **RECOMMENDED**

Best for automated Virtualizor deployments with configuration validation:

```bash
# 1. Download recipe with runtime configuration injection
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh

# 2. Edit ONLY the configuration section
nano direct-download-recipe.sh

# 3. Replace with YOUR actual values:
ZABBIX_SERVER_DOMAIN="monitoring.yourcompany.com"   # YOUR server
SSH_TUNNEL_PORT="8472"                             # YOUR unique port
SSH_TUNNEL_USER="acme-monitoring-agent"            # YOUR unique username
ZABBIX_VERSION="6.4"                               # Version to install
ZABBIX_SERVER_PORT="10051"                         # Zabbix port

# 4. Upload to Virtualizor - it handles the rest automatically!
```

### **Method 2: Environment Variables** (Manual execution)

Best for direct script execution outside Virtualizor:

```bash
# Set environment variables before script execution
export ZABBIX_SERVER_DOMAIN="monitoring.yourcompany.com"
export SSH_TUNNEL_PORT="8472"
export SSH_TUNNEL_USER="acme-monitoring-agent"
export ZABBIX_VERSION="6.4"
export ZABBIX_SERVER_PORT="10051"

# Execute script with environment
curl -fsSL https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh | bash
```

### **Method 3: Command-Line Parameters** (Manual execution)

Best for direct script execution with explicit parameters:

```bash
wget -O /tmp/setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
chmod +x /tmp/setup.sh

./setup.sh \
    --ssh-host "monitoring.yourcompany.com" \
    --ssh-port "8472" \
    --ssh-user "acme-monitoring-agent" \
    --zabbix-version "6.4" \
    --zabbix-server-port "10051"
```

## 🎯 Virtualizor Recipe Deployment (Runtime Injection)

### **Step 1: Download and Customize Recipe**

```bash
# Download the smart recipe with runtime configuration injection
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh

# Edit configuration section with YOUR infrastructure details
nano direct-download-recipe.sh
```

### **Step 2: Configure YOUR Infrastructure Values**

**Edit ONLY these lines in the recipe file:**

```bash
# =============================================================================
# CONFIGURATION SECTION - EDIT THESE VALUES FOR YOUR ENVIRONMENT  
# =============================================================================

# ⚠️ MANDATORY: CUSTOMIZE THESE VALUES FOR YOUR INFRASTRUCTURE
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ YOUR monitoring server
SSH_TUNNEL_PORT="2847"                           # ⚠️ YOUR unique SSH port
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ YOUR unique username
ZABBIX_VERSION="6.4"                             # Zabbix version to install
ZABBIX_SERVER_PORT="10051"                       # Zabbix server port
```

### **Step 3: Security Validation (Minimal)**

The recipe performs minimal validation to prevent accidental deployment:

- ❌ **Blocks example domain**: `monitor.yourcompany.com`
- ✅ **Administrator Trust**: Trusts administrators to configure appropriate security settings
- ✅ **Clean Configuration**: Single configuration path without security vulnerabilities

### **Step 4: Deploy in Virtualizor**

1. **Upload recipe** to Virtualizor as "Post Installation Script"
2. **Apply to VM plans** - recipe runs automatically during server creation  
3. **Monitor logs** at `/var/log/virtualizor-recipe.log` for execution status

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
SSH_TUNNEL_PORT="2847"         # Administrator-chosen unique port
SSH_TUNNEL_USER="zbx-tun-usr"  # Administrator-chosen unique username
```

**Note**: Administrators are responsible for choosing appropriate security settings.

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
# Fix: Update ZABBIX_SERVER_DOMAIN with your actual monitoring server domain
```

**Note**: Recipe performs minimal validation - administrators are trusted to configure appropriate security settings.

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
