# Runtime Configuration Injection Guide

## 🚀 The Revolutionary Approach to Virtualizor Automation

**The Challenge**: Traditional automation required configuring servers before they existed during Virtualizor provisioning.

**✅ Our Solution**: **Runtime Configuration Injection** - Download scripts and inject your configuration values during server creation.

## 💡 How Runtime Configuration Injection Works

```text
┌─ Virtualizor Recipe Execution ─┐
│                                │
│ 1. Recipe starts during        │
│    server provisioning        │
│                                │
│ 2. Downloads master script     │
│    from GitHub                 │
│                                │
│ 3. Uses sed to inject YOUR     │
│    configuration values        │
│                                │
│ 4. Executes configured script  │
│    automatically               │
│                                │
│ ✅ Server ready for monitoring │
└────────────────────────────────┘
```

## 🔧 Implementation Details

### **Configuration Injection Process**

The recipe performs these operations automatically:

```bash
# 1. Download the latest master script
curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT"

# 2. Inject YOUR configuration values using sed
sed -i "s|DEFAULT_HOME_SERVER_IP=.*|DEFAULT_HOME_SERVER_IP=\"$ZABBIX_SERVER_DOMAIN\"|g" "$TEMP_SCRIPT"
sed -i "s|SSH_TUNNEL_PORT=.*|SSH_TUNNEL_PORT=\"$SSH_TUNNEL_PORT\"|g" "$TEMP_SCRIPT"
sed -i "s|SSH_TUNNEL_USER=.*|SSH_TUNNEL_USER=\"$SSH_TUNNEL_USER\"|g" "$TEMP_SCRIPT"

# 3. Execute the configured script with your settings
"$TEMP_SCRIPT" --ssh-host "$ZABBIX_SERVER_DOMAIN" \
               --ssh-port "$SSH_TUNNEL_PORT" \
               --ssh-user "$SSH_TUNNEL_USER"
```

### **Security Validation System**

Built-in validation prevents production failures:

```bash
# Simple validation check:
✅ Blocks example domain: "monitor.yourcompany.com"
❌ Exits with error if example value detected in production
```

**Administrator Trust Model**: The recipe trusts system administrators to properly configure values before deployment. Only the placeholder domain is validated to prevent accidental deployment with example values.

## 🎯 Step-by-Step Implementation

### **Step 1: Download Recipe with Runtime Injection**

```bash
# Get the smart recipe with built-in configuration injection
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh
```

### **Step 2: Configure YOUR Infrastructure**

Edit **ONLY** the configuration section (lines 15-20):

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

**Replace with YOUR actual values:**
```bash
# Example customization:
ZABBIX_SERVER_DOMAIN="zabbix.internal.acme.com"
SSH_TUNNEL_PORT="8472"                           
SSH_TUNNEL_USER="acme-monitoring-agent"          
ZABBIX_VERSION="6.4"                             
ZABBIX_SERVER_PORT="10051"                       
```

### **Step 3: Upload to Virtualizor**

1. **Access Virtualizor admin panel**
2. **Navigate to**: Plans → Recipes → Add Recipe
3. **Recipe Type**: Post Installation Script
4. **Upload your configured recipe file**
5. **Apply to server templates**

### **Step 4: Automated Execution**

The recipe runs automatically during server provisioning:

```text
🎯 Recipe starts → 🌐 Network wait → 📥 Script download → 
⚙️ Config injection → 🚀 Execution → ✅ Server ready
```

## 🔒 Security Features

### **Automatic Configuration Validation**

```bash
# The recipe validates only essential configuration:
if [[ "$ZABBIX_SERVER_DOMAIN" == "monitor.yourcompany.com" ]]; then
    log_message "❌ ERROR: Using example domain '$ZABBIX_SERVER_DOMAIN'"
    log_message "   You must edit this recipe and set your actual monitoring server!"
    exit 1
fi
```

### **Administrator Trust Model**

- **Minimal Validation**: Only prevents deployment with placeholder example domain
- **Administrator Responsibility**: System administrators are trusted to configure appropriate security settings
- **Clean Configuration**: No multiple fallback options that could create security vulnerabilities

## 📊 Benefits of Runtime Injection

### **✅ Advantages**

- **No Pre-Configuration**: Configure non-existent servers during creation
- **Always Current**: Downloads latest script version automatically
- **Security Validated**: Built-in checks prevent insecure configurations
- **Network Resilient**: Multiple fallback download methods
- **Audit Trail**: Complete logging of all operations
- **Zero Touch**: Fully automated execution after recipe configuration

### **📋 Comparison with Traditional Approaches**

| Feature | Pre-Configuration | Runtime Injection |
|---------|------------------|-------------------|
| Server Exists | ❌ Required | ✅ Not needed |
| Always Current | ❌ Manual updates | ✅ Auto-downloads latest |
| Security Validation | ❌ Manual | ✅ Built-in |
| Network Issues | ❌ Single point failure | ✅ Multiple fallbacks |
| Configuration Errors | ❌ Silent failures | ✅ Immediate feedback |
| Automation Ready | ❌ Manual steps | ✅ Zero touch |

## 🛠️ Troubleshooting Runtime Injection

### **Common Issues and Solutions**

#### **1. Configuration Validation Failures**
```bash
# Error: "Using example domain 'monitor.yourcompany.com'"
# Solution: Edit recipe file and replace with your actual monitoring server
ZABBIX_SERVER_DOMAIN="your-actual-monitoring-server.com"
```

#### **2. Network Download Issues**
```bash
# The recipe has built-in fallbacks:
# 1. Tries curl first
# 2. Falls back to wget
# 3. Multiple retry attempts
# 4. Comprehensive error logging
```

#### **3. Configuration Injection Verification**
```bash
# Check if values were injected:
grep "your-actual-server" /tmp/virtualizor-server-setup.sh
# Should show your configuration values in the downloaded script
```

### **Debug Information**

Monitor recipe execution:
```bash
# Recipe logs all operations:
tail -f /var/log/virtualizor-recipe.log

# Setup script logs:
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-*.log
```

## 🎉 Success Indicators

### **Recipe Completion Messages**

```bash
[2025-07-21 10:30:45] ✅ Configuration validation passed
[2025-07-21 10:30:47] ✅ Network connectivity confirmed  
[2025-07-21 10:30:52] ✅ Script downloaded and made executable
[2025-07-21 10:30:53] ✅ Configuration values successfully injected into script
[2025-07-21 10:35:28] ✅ Server setup completed successfully
[2025-07-21 10:35:28] 🎉 Virtualizor recipe completed successfully!
[2025-07-21 10:35:28]    Server is now ready for monitoring
```

### **Verification Steps**

After successful recipe execution:

```bash
# 1. Check Zabbix agent status:
systemctl status zabbix-agent

# 2. Verify SSH tunnel configuration:
ls -la /root/.ssh/zabbix_*

# 3. Test monitoring connectivity:
zabbix_agentd -t system.hostname

# 4. Review setup summary:
cat /var/log/zabbix-scripts/virtualizor-server-setup-*.log | grep "Setup summary"
```

---

**🎯 Result**: Your servers are automatically configured for monitoring during Virtualizor provisioning with zero manual intervention required!
