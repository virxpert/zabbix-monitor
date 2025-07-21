# Virtualizor Recipe Templates

This directory contains production-ready Virtualizor recipe templates for **automated server provisioning** with the `virtualizor-server-setup.sh` script.

## 📋 Available Recipe

### **[direct-download-recipe.sh](direct-download-recipe.sh)** ⭐ RECOMMENDED

- **Simple & Clean**: 64-line concise script for fast provisioning
- **Method**: Downloads latest script from GitHub and passes your configuration as parameters
- **Advantages**: Always current, small size, easy to understand and maintain
- **Usage**: Edit configuration section, then copy entire content to Virtualizor recipe configuration

## 🚀 Quick Setup

1. **Download recipe**: `wget https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh`
2. **Edit configuration**: Update lines 13-17 with your actual server details
3. **Upload to Virtualizor**: Copy entire script content to recipe configuration
4. **Test deployment**: Run on a test VPS first to validate

## 📝 Configuration Required

**You MUST edit these values in the recipe (lines 13-17):**

```bash
ZABBIX_SERVER_DOMAIN="monitor.yourcompany.com"    # ⚠️ YOUR monitoring server
SSH_TUNNEL_PORT="2847"                           # ⚠️ YOUR unique SSH port  
SSH_TUNNEL_USER="zbx-tunnel-user"                # ⚠️ YOUR unique username
ZABBIX_VERSION="6.4"                             # Zabbix version to install
ZABBIX_SERVER_PORT="10051"                       # Zabbix server port
```

**Replace with YOUR actual values** before uploading to Virtualizor.

## 📚 Documentation

- **[Complete Integration Guide](../docs/virtualizor-recipe-integration.md)** - Step-by-step instructions
- **[Diagnostic Tool](../scripts/virtualizor-recipe-diagnostic.sh)** - Troubleshoot recipe issues
- **[Main README](../README.md)** - Full project documentation

## ✅ What These Recipes Accomplish

Each recipe provides **completely automated server setup**:

- 🔄 System updates and reboots (with persistence)
- 📦 Zabbix agent installation and configuration  
- 🔑 SSH key generation (unique per server)
- 🌐 SSH tunnel service creation
- 🎯 Complete monitoring setup
- 🎨 Custom server banners and MOTD
- 🧹 Automatic cleanup and finalization

## 🔧 Troubleshooting

If a recipe fails to execute:

1. **Check logs**: `/var/log/virtualizor-recipe.log`
2. **Run diagnostic**: `./virtualizor-recipe-diagnostic.sh`
3. **Verify network**: `ping 8.8.8.8`
4. **Manual execution**: Download and run script manually
5. **Review guide**: [Recipe Integration Documentation](../docs/virtualizor-recipe-integration.md)

## 📞 Support

For issues with recipe integration:

- Check the [Troubleshooting Guide](../docs/troubleshooting-guide.md)
- Review [Recipe Integration Guide](../docs/virtualizor-recipe-integration.md)
- Create [GitHub Issue](https://github.com/virxpert/zabbix-monitor/issues) with recipe logs
