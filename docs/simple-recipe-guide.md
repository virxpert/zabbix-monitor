# Simple Recipe Configuration Guide

## 🚀 Clean Approach to Virtualizor Automation

**The Problem**: How to configure servers that don't exist yet during automated provisioning?

**Our Solution**: Simple parameter passing - download script and pass your configuration as command-line parameters.

## 💡 How It Works

```text
┌─ Virtualizor Recipe (64 lines) ─┐
│                                 │
│ 1. Validates configuration      │
│ 2. Waits for network           │ 
│ 3. Downloads master script     │
│ 4. Passes YOUR parameters      │
│ 5. Server setup completes      │
│                                 │
│ ✅ Fully configured server     │
└─────────────────────────────────┘
```

## 🎯 Quick Start

### Step 1: Get the Recipe

```bash
wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh
```

### Step 2: Configure (Edit Lines 13-17)

```bash
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ Change this
SSH_TUNNEL_PORT="2847"                           # ⚠️ Your unique port
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ Your unique user
ZABBIX_VERSION="6.4"                             # Zabbix version
ZABBIX_SERVER_PORT="10051"                       # Server port
```

**Replace with your actual values:**
```bash
ZABBIX_SERVER_DOMAIN="zabbix.acme.com"          # Your real server
SSH_TUNNEL_PORT="8472"                           # Unique port
SSH_TUNNEL_USER="acme-monitoring"                # Company username
```

### Step 3: Upload to Virtualizor

1. Copy entire recipe content
2. Paste into Virtualizor recipe configuration
3. Test on development VPS first
4. Deploy to production

## 🛡️ Built-in Safety

**Single validation check:**
- ✅ Prevents using placeholder domain `monitor.yourcompany.com`
- ✅ Trusts administrators to configure appropriately
- ✅ No complex validation that could create confusion

## 🔧 Troubleshooting

**Recipe fails with "Must update ZABBIX_SERVER_DOMAIN"**
- Edit recipe and change `monitor.yourcompany.com` to your real server

**Download fails**
- Check internet: `ping 8.8.8.8`
- Check GitHub access: `wget https://github.com`

**Setup fails after download**
- Check logs: `tail -f /var/log/virtualizor-recipe.log`

## ✅ Why This Works Better

- **Simple**: Only 64 lines (vs 288+ in complex versions)
- **Clear**: No confusing sed/awk file manipulation
- **Reliable**: Direct parameter passing
- **Fast**: Minimal operations, quick provisioning
- **Maintainable**: Easy to understand and modify

## 📞 Need Help?

- Recipe logs: `/var/log/virtualizor-recipe.log`
- Main docs: [README.md](../README.md)
- Issues: [GitHub Issues](https://github.com/virxpert/zabbix-monitor/issues)
