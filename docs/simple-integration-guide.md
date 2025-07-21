# Virtualizor Recipe Integration Guide

This guide explains how to integrate Zabbix monitoring into Virtualizor recipes using our **simple recipe approach** for automated server provisioning.

## 🎯 The Solution

**Problem**: Configure servers that don't exist yet during automated provisioning.

**Solution**: Simple parameter passing - download script and pass configuration as parameters.

## 🚀 Quick Integration

### Step 1: Get the Recipe

```bash
# Download the simple 64-line recipe
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh
```

### Step 2: Configure (Edit Lines 13-17)

```bash
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ Change this
SSH_TUNNEL_PORT="2847"                           # ⚠️ Unique port
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ Unique user
ZABBIX_VERSION="6.4"                             # Version
ZABBIX_SERVER_PORT="10051"                       # Server port
```

**Replace with YOUR values:**
```bash
ZABBIX_SERVER_DOMAIN="zabbix.acme.com"          # Your monitoring server
SSH_TUNNEL_PORT="8472"                           # Your unique port  
SSH_TUNNEL_USER="acme-monitoring"                # Your username
```

### Step 3: Upload to Virtualizor

1. **Login** to Virtualizor admin panel
2. **Navigate**: Plans → Recipes → Add Recipe  
3. **Type**: Post Installation Script
4. **Content**: Copy entire recipe and paste
5. **Test**: Deploy on development VPS first
6. **Production**: Apply to server templates

## 🛡️ Built-in Safety

**Automatic validation:**
- ✅ Prevents using placeholder domain `monitor.yourcompany.com`
- ✅ Exits with clear error if example values detected
- ✅ Trusts administrators to configure appropriately

## 🔧 Troubleshooting

**Configuration Error**: "Must update ZABBIX_SERVER_DOMAIN"
- Solution: Replace `monitor.yourcompany.com` with your actual server

**Download Error**: "Download failed"  
- Check: Internet connectivity (`ping 8.8.8.8`)
- Check: GitHub access (`wget https://github.com`)

**Setup Error**: Script fails after download
- Check: Recipe logs at `/var/log/virtualizor-recipe.log`
- Review: Master script documentation

## ✅ What You Get

After recipe execution, each server automatically has:

- 🔄 **System updates** and reboots handled
- 📦 **Zabbix agent** installed and configured  
- 🔑 **SSH keys** generated (unique per server)
- 🌐 **SSH tunnel** service configured
- 🎯 **Monitoring** fully operational
- 📋 **Logs** available for troubleshooting

## 📋 Recipe Workflow

```text
Recipe Start → Configuration Check → Network Wait → 
Script Download → Parameter Passing → Setup Execution → 
Complete Server Ready for Monitoring
```

**Total time**: Typically 3-5 minutes per server

## 📞 Support

**Documentation:**
- [Simple Recipe Guide](simple-recipe-guide.md)
- [Main README](../README.md)
- [Troubleshooting Guide](troubleshooting-guide.md)

**Logs:**
- Recipe: `/var/log/virtualizor-recipe.log`
- Setup: `/var/log/zabbix-scripts/virtualizor-server-setup-*.log`

**Issues:**
- [GitHub Issues](https://github.com/virxpert/zabbix-monitor/issues)
