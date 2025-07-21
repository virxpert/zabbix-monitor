# Virtualizor Recipe Integration Guide

This guide explains how to properly integrate the `virtualizor-server-setup.sh` script into Virtualizor recipes for completely touchless server provisioning.

## Problem Analysis

The script didn't run automatically because of **Virtualizor recipe configuration issues**, not problems with the script itself. Common issues include:

- **Missing script files** - Script not uploaded to server
- **Syntax errors** in recipe code (mismatched quotes, parentheses)
- **Network timing** - Script runs before network is ready
- **File permissions** - Script not executable
- **Path issues** - Wrong file paths in recipe

## Solution Options

### Option 1: Direct Download Recipe (Recommended)

**Best for**: Production environments with internet access

```bash
#!/bin/bash
# Virtualizor Recipe: Direct Download Method
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh"
LOG_FILE="/var/log/virtualizor-recipe.log"

# Wait for network
for i in {1..30}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then break; fi
    sleep 2
done

# Download and execute
wget -O /tmp/setup.sh "$SCRIPT_URL"
chmod +x /tmp/setup.sh
/tmp/setup.sh --banner-text "Virtualizor Managed Server - READY"
```

**Advantages:**
- ✅ Always gets latest script version
- ✅ Small recipe size
- ✅ Easy to maintain
- ✅ No script duplication

### Option 2: Embedded Script Recipe

**Best for**: Air-gapped environments or when you want script versioning control

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
