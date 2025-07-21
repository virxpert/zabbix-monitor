# Virtualizor Recipe Integration Guide

This guide explains how to integrate the Zabbix monitoring setup into Virtualizor recipes using **runtime configuration injection** for automated server provisioning.

## � Runtime Configuration Injection - The Solution

**✅ The Problem Solved**: Traditional approaches required pre-configuring servers that don't exist yet during automated provisioning. Our new approach downloads scripts and injects configuration values at runtime during server creation.

### How Runtime Configuration Injection Works

1. **Recipe Execution**: Virtualizor runs your recipe during server provisioning
2. **Script Download**: Recipe downloads the latest master script from GitHub
3. **Configuration Injection**: Recipe uses `sed` to inject YOUR configuration values into the downloaded script
4. **Automated Execution**: Modified script runs with your settings - no manual intervention needed

## 📋 Step-by-Step Integration

### Step 1: Choose Your Recipe (Runtime Injection Enabled)

**✅ Option 1: Direct Download Recipe (Recommended)**
- **Runtime injection**: Downloads and configures script during provisioning
- **Always current**: Gets the latest script version automatically  
- **Network resilient**: Multiple fallback download methods
- **Security validated**: Prevents using example values in production

**✅ Option 2: Smart Dynamic Recipe (Alternative)**
- **Same functionality**: Identical runtime configuration injection
- **Clean implementation**: More focused code structure
- **Full validation**: Complete security and configuration checking

### Step 2: Download and Configure Recipe

**For Runtime Configuration Injection:**

```bash
# 1. Download the recipe with runtime configuration injection
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh

# 2. Edit ONLY the configuration section (lines 15-20)
nano direct-download-recipe.sh

# 3. Replace these values with YOUR actual infrastructure details:
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ YOUR monitoring server
SSH_TUNNEL_PORT="2847"                           # ⚠️ YOUR unique SSH port  
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ YOUR unique username
ZABBIX_VERSION="6.4"                             # Zabbix version to install
ZABBIX_SERVER_PORT="10051"                       # Zabbix server port

# 4. Save file - ready for Virtualizor upload
```

### Step 3: Security Validation (Built-In)

**The recipe automatically validates your configuration:**

✅ **Prevents Example Values**: Refuses to run with placeholder domain "monitor.yourcompany.com"
✅ **Administrator Trust**: Trusts system administrators to configure appropriate security settings
✅ **Clean Configuration**: No multiple fallback options that could create security vulnerabilities
✅ **Production Safety**: Won't deploy with example domain value

**Manual validation (optional):**
```bash
# Check that you replaced the example value:
grep "monitor\.yourcompany\.com" your-recipe.sh
# Should return NO results (meaning you updated it)

# Verify your actual configuration:
grep "ZABBIX_SERVER_DOMAIN=" your-recipe.sh
# Should show YOUR actual monitoring server
```

### Step 4: Upload and Deploy in Virtualizor

1. **Login to Virtualizor admin panel**
2. **Navigate to**: Plans → Recipes → Add Recipe
3. **Recipe Type**: Post Installation Script  
4. **Upload your configured recipe file**
5. **Assign to VM plans** as needed
6. **Test deployment** on development VM first

## 🔧 Recipe Configuration Examples

### Minimal Configuration (Required)

```bash
# In your recipe file - CONFIGURATION SECTION
export ZABBIX_SERVER_DOMAIN="monitor.acme.com"      # Your monitoring server
export SSH_TUNNEL_PORT="2847"                       # Your unique SSH port
export SSH_TUNNEL_USER="acme-zbx-user"              # Your unique username
```

### Complete Configuration (Recommended)

```bash  
# Complete configuration for production deployment
export ZABBIX_SERVER_DOMAIN="zabbix.internal.acme.com"
export SSH_TUNNEL_PORT="8472"                       # Non-standard port
export SSH_TUNNEL_USER="acme-monitoring-agent"      # Company-specific username
export ZABBIX_VERSION="6.4"                         # Specific version
export ZABBIX_SERVER_PORT="10051"                   # Zabbix server port

# Optional: Custom banner
DEFAULT_BANNER_TEXT="ACME Corp Production Server - Monitoring Enabled"
```

1. Copy the complete content of `virtualizor-server-setup.sh`
2. Embed it in the recipe template provided in `/virtualizor-recipes/embedded-script-recipe.sh`
3. Replace the `# === INSERT COMPLETE virtualizor-server-setup.sh CONTENT HERE ===` section

**Advantages:**
- ✅ No network dependency
- ✅ Version control
- ✅ Works in isolated environments
- ✅ Faster execution (no download)

### Option 3: Cloud-Init Compatible Recipe

**Best for**: Environments using cloud-init or when you need delayed execution

Uses systemd service for first-boot execution after network is fully ready.

**Advantages:**
- ✅ Network timing resilient
- ✅ Cloud-init compatible
- ✅ Delayed execution support
- ✅ Automatic cleanup

## Recipe Configuration Steps

### Step 1: Choose Your Recipe Type
Select one of the three options above based on your environment needs.

### Step 2: Configure Virtualizor Recipe
1. **Access Virtualizor Admin Panel**
2. **Go to**: Recipes → Add Recipe
3. **Recipe Type**: Post Installation
4. **Shell**: `/bin/bash`
5. **Content**: Paste your chosen recipe content

### Step 3: Test Recipe
1. **Create test VPS** using the recipe
2. **Monitor logs**: `/var/log/virtualizor-recipe.log`
3. **Verify setup**: SSH to server and check banner
4. **Check services**: `systemctl status zabbix-agent zabbix-tunnel`

### Step 4: Production Deployment
Once tested, apply recipe to production VPS templates.

## Troubleshooting Virtualizor Recipes

### Common Recipe Issues

#### 1. Syntax Errors
```bash
# BAD - Unmatched quotes
echo "Hello world'

# GOOD - Matched quotes
echo "Hello world"
```

#### 2. Network Timing
```bash
# BAD - No network wait
wget http://example.com/script.sh

# GOOD - Wait for network
for i in {1..30}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then break; fi
    sleep 2
done
wget http://example.com/script.sh
```

#### 3. Missing Error Handling
```bash
# BAD - No error checking
wget script.sh
chmod +x script.sh
./script.sh

# GOOD - With error checking
set -euo pipefail
if ! wget -O script.sh "https://example.com/script.sh"; then
    echo "Download failed"
    exit 1
fi
chmod +x script.sh
if ! ./script.sh; then
    echo "Script execution failed"
    exit 1
fi
```

### Debug Recipe Execution

#### Check Recipe Logs
```bash
# Virtualizor recipe logs
ls -la /root/recipe_*.log
cat /root/recipe_*.log

# System boot logs
journalctl -b 0 | grep -i "recipe\|virtualizor"

# Custom recipe logs
tail -f /var/log/virtualizor-recipe.log
```

#### Validate Network Connectivity
```bash
# Test basic connectivity
ping -c 2 8.8.8.8

# Test HTTPS access
wget --timeout=10 --tries=3 -O /dev/null https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
```

#### Manual Script Execution
```bash
# Download manually
wget -O /tmp/test-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh

# Make executable
chmod +x /tmp/test-setup.sh

# Test execution
/tmp/test-setup.sh --test --banner-text "Test Server"
```

## Recipe Best Practices

### 1. Always Use Error Handling
```bash
set -euo pipefail  # Exit on errors
```

### 2. Include Logging
```bash
LOG_FILE="/var/log/virtualizor-recipe.log"
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
```

### 3. Wait for Network
```bash
# Network connectivity check
for i in {1..30}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then break; fi
    sleep 2
done
```

### 4. Validate Downloads
```bash
# Check file size and integrity
if [ ! -s "/tmp/script.sh" ]; then
    echo "ERROR: Downloaded file is empty"
    exit 1
fi
```

### 5. Clean Up Temporary Files
```bash
# Clean up at the end
rm -f /tmp/setup.sh /tmp/virtualizor-recipe.log
```

## Testing Your Recipe

### 1. Create Test VPS
- Use minimal OS template
- Apply your recipe
- Monitor creation process

### 2. Validate Results
```bash
# Check script execution
grep "completed successfully" /var/log/zabbix-scripts/virtualizor-server-setup-*.log

# Check services
systemctl status zabbix-agent
systemctl status zabbix-tunnel

# Check SSH keys
ls -la /root/.ssh/zabbix_tunnel_key*
cat /root/zabbix_tunnel_public_key.txt
```

### 3. Test SSH Tunnel
```bash
# Test tunnel connectivity
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in
```

## Production Deployment

### 1. Update Recipe Templates
Apply working recipe to your VPS templates in Virtualizor.

### 2. Monitor Deployments
- Watch recipe execution logs
- Verify successful completions
- Check for any failures

### 3. Document Configuration
- Save working recipe configuration
- Document any customizations
- Update operational procedures

## Summary

The original issue was **not with the script** but with **Virtualizor recipe configuration**. Our script works perfectly (as proven by manual testing), but needs proper integration into Virtualizor recipes.

Use the provided recipe templates to achieve completely **touchless server provisioning** with full Zabbix monitoring setup.
