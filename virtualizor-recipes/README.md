# Virtualizor Recipe Templates

This directory contains production-ready Virtualizor recipe templates for completely **touchless server provisioning** with the `virtualizor-server-setup.sh` script.

## 📋 Available Recipes

### 1. **[direct-download-recipe.sh](direct-download-recipe.sh)** ⭐ RECOMMENDED
- **Best for**: Production environments with internet access
- **Method**: Downloads latest script from GitHub automatically
- **Advantages**: Always current, small recipe size, easy maintenance
- **Usage**: Copy entire content to Virtualizor recipe configuration

### 2. **[embedded-script-recipe.sh](embedded-script-recipe.sh)**  
- **Best for**: Air-gapped environments or version control requirements
- **Method**: Contains complete script embedded within recipe
- **Advantages**: No network dependency, works offline, version control
- **Usage**: Replace placeholder section with complete `virtualizor-server-setup.sh` content

### 3. **[cloud-init-compatible-recipe.sh](cloud-init-compatible-recipe.sh)**
- **Best for**: Cloud-init environments or delayed execution needs
- **Method**: Uses systemd service for first-boot execution
- **Advantages**: Network timing resilient, cloud-init compatible
- **Usage**: Creates systemd service for automated first-boot execution

## 🚀 Quick Setup

1. **Choose your recipe** based on environment needs
2. **Copy recipe content** to Virtualizor recipe configuration
3. **Test with single VPS** to validate execution
4. **Deploy to production** templates once verified

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
