# Zabbix Monitoring Scripts for Virtualizor Provisioning

> **📅 Latest Updates (July 21, 2025)**: Major improvements applied for phased updates handling, cross-platform compatibility, systemd service reliability, and enhanced error recovery. See [Recent Updates](#-recent-updates-july-2025) section for complete details.

This repository contains a **single, comprehensive server provisioning script** designed specifically for **Virtualizor software recipes**. The script handles the complete Linux server setup lifecycle including system updates, reboots, Zabbix agent installation, and SSH tunnel configuration with full state persistence.

> **🎯 IMPORTANT: You only need to run ONE script (`virtualizor-server-setup.sh`) on each guest server. This single script does everything automatically - no need for multiple scripts or complex configurations.**

## 🚀 Quick Start - ONE Script Does Everything

**Architecture**: **One Zabbix Server** monitors **many guest servers** via individual SSH tunnels.

**You only need to run ONE script on each guest/agent server:**

```bash
# Download and execute the master provisioning script
wget -O /tmp/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh
chmod +x /tmp/virtualizor-server-setup.sh

# Execute complete server setup (handles everything automatically)
/tmp/virtualizor-server-setup.sh
```

**What this ONE script does:**
- 🔄 System updates and reboots (with state persistence)
- 📦 Zabbix agent installation and configuration
- 🔑 SSH key generation for secure tunnels (unique per server)
- 🌐 SSH tunnel service creation and setup
- 🎯 Complete monitoring configuration for multi-server environment

## 🏗️ Architecture

### Master Script Approach
**`virtualizor-server-setup.sh`** - **The ONLY script you need to run:**
- ✅ **Complete Provisioning** - Handles entire server lifecycle in one execution
- ✅ **Reboot Persistent** - Maintains state across system reboots
- ✅ **Conflict Prevention** - Single execution point eliminates race conditions  
- ✅ **Stage Management** - Progresses through defined stages automatically
- ✅ **Recovery Support** - Can resume from any stage if interrupted

## 🔄 Simple Workflow - Multi-Server Environment

### **Architecture Overview**
```
[Guest Server 1] ----SSH Tunnel---> 
[Guest Server 2] ----SSH Tunnel---> [Monitor Server:20202] --> [Zabbix Server:10051]
[Guest Server 3] ----SSH Tunnel---> 
[Guest Server N] ----SSH Tunnel---> 
```

**One Zabbix Server** monitors **unlimited guest servers** via individual encrypted SSH tunnels.

### For Each Guest Server (Repeat for All Servers)
1. **Run the script** (everything automated):
   ```bash
   ./virtualizor-server-setup.sh
   ```

2. **Copy the displayed SSH key** (unique per server) to your Zabbix server:
   ```bash
   # Script shows unique key: ssh-rsa AAAAB3... zabbix-tunnel-hostname-20250721
   # Add to: /home/zabbixssh/.ssh/authorized_keys (append, don't overwrite)
   ```

3. **Add host in Zabbix web interface** (each server uses same tunnel endpoint):
   - **Host name**: Unique server hostname
   - **IP address**: `127.0.0.1` (all servers use tunnel)
   - **Port**: `10050` (standard for all)

## 🔑 Administrator SSH Key Access

After server provisioning, administrators can find SSH keys at:

```bash
# Key files (on each guest server)
/root/.ssh/zabbix_tunnel_key          # Private key
/root/.ssh/zabbix_tunnel_key.pub      # Public key

# Administrator documentation (on each guest server)
/root/zabbix_ssh_key_info.txt         # Complete setup instructions
/root/zabbix_tunnel_public_key.txt    # Public key for copy/paste

# Quick access commands
cat /root/zabbix_ssh_key_info.txt     # View setup instructions
systemctl status zabbix-tunnel        # Check tunnel status
```

**Note**: Customer-facing server banners show only "Server Ready" status. Technical monitoring details are available in administrator files above.

### **Key Benefits**
- ✅ **Unlimited Scaling**: Add servers without limit
- ✅ **Secure Isolation**: Each server has unique SSH key
- ✅ **Single Management Point**: One Zabbix server, one SSH user
- ✅ **Automatic Configuration**: Script handles all complexity

**That's it!** The same process works for 2 servers or 200 servers.

> **💡 IMPORTANT: This is a SINGLE-SCRIPT solution. You don't need to run multiple scripts, manage configurations, or handle complex setups. Just run `virtualizor-server-setup.sh` and follow the simple 3-step process above.**

### Archived Components
Legacy individual scripts have been moved to `/archive/legacy-scripts/` and are no longer recommended for production use. See `/archive/README.md` for details.

## 📋 Provisioning Stages

The master script progresses through these stages automatically:

1. **INIT** - System detection and validation
2. **BANNER** - Set login banners and MOTD  
3. **UPDATES** - Install system updates/upgrades
4. **POST-REBOOT** - Post-update system validation
5. **ZABBIX-INSTALL** - Install and configure Zabbix agent
6. **ZABBIX-CONFIGURE** - Configure for tunnel connectivity
7. **TUNNEL-SETUP** - Create SSH tunnel service
8. **COMPLETE** - Finalize setup and cleanup

## 🔄 Reboot Handling

The script automatically handles system reboots during updates:
- **State Files**: Execution state saved to `/var/run/virtualizor-server-setup.state`

## 📚 Documentation

### Server Configuration Guides
- **[Zabbix Server Configuration](docs/zabbix-server-configuration.md)** - Complete server-side setup instructions
- **[SSH Tunnel Setup Guide](docs/ssh-tunnel-setup-guide.md)** - Quick reference for tunnel configuration
- **[Troubleshooting Guide](docs/troubleshooting-guide.md)** - Common issues and solutions
- **[Administrator SSH Key Access](docs/administrator-ssh-key-access.md)** - How to retrieve SSH keys during provisioning

### Key Configuration Requirements
Before running the provisioning script on guest servers, ensure the Zabbix server is properly configured for **multi-server SSH tunnel management**:

1. **SSH Tunnel User**: Create `zabbixssh` user on monitoring server (handles ALL guest connections)
2. **SSH Service**: Configure SSH on port 20202 with tunneling enabled (single port for all guests)
3. **Firewall**: Open ports 20202 (SSH) and 10051 (Zabbix) on monitoring server
4. **Public Keys**: Append each guest's public key to server's `authorized_keys` file
5. **Zabbix Hosts**: Configure individual hosts in Zabbix web interface (all use `127.0.0.1:10050`)

**Multi-Server Architecture**: Each guest server creates a unique SSH tunnel to the same monitoring server endpoint, allowing unlimited scaling with single-point management.

See [SSH Tunnel Setup Guide](docs/ssh-tunnel-setup-guide.md) for step-by-step instructions.
- **Systemd Service**: Temporary service created for post-reboot continuation
- **Automatic Resume**: Script continues from saved stage after reboot
- **No Intervention**: Completely hands-off operation

## ⚙️ Configuration

All configuration is embedded within the master script. Modify these defaults as needed:

```bash
# SSH Tunnel Settings
DEFAULT_HOME_SERVER_IP="monitor.cloudgeeks.in"
DEFAULT_HOME_SERVER_SSH_PORT=20202
DEFAULT_SSH_USER="zabbixssh"

# Zabbix Settings  
DEFAULT_ZABBIX_VERSION="6.4"
DEFAULT_ZABBIX_SERVER_PORT=10051

# Banner Settings
DEFAULT_BANNER_TEXT="Virtualizor Managed Server - Setup in Progress"
DEFAULT_MOTD_MESSAGE="WARNING: Authorized Access Only
*   This VPS is the property of Everything Cloud Solutions *
*   Unauthorized use is strictly prohibited and monitored. *
*   For any issue, report it to support@everythingcloud.ca *"
```

## 🔧 Usage Examples

### Virtualizor Recipe (Recommended)
```bash
# Basic execution - uses all defaults
./virtualizor-server-setup.sh

# Custom configuration
./virtualizor-server-setup.sh \
    --banner-text "Production Server - ACME Corp" \
    --ssh-host "monitor.acme.com" \
    --zabbix-version "6.4"
```

### Manual Operations  
```bash
# Check current status
./virtualizor-server-setup.sh --status

# Test configuration without changes
./virtualizor-server-setup.sh --test

# Start from specific stage
./virtualizor-server-setup.sh --stage zabbix-install

# Clean up after failed run
./virtualizor-server-setup.sh --cleanup
```

## 📊 Monitoring & Logs

### Log Files
- **Setup Logs**: `/var/log/zabbix-scripts/virtualizor-server-setup-YYYYMMDD.log`
- **System Logs**: `journalctl -u virtualizor-server-setup.service`
- **Zabbix Agent**: `/var/log/zabbix/zabbix_agentd.log`
- **SSH Tunnel**: `journalctl -u zabbix-tunnel.service`

### Status Monitoring
```bash
# Watch setup progress in real-time
tail -f /var/log/zabbix-scripts/virtualizor-server-setup-$(date +%Y%m%d).log

# Check service status
systemctl status zabbix-agent
systemctl status zabbix-tunnel

# View current setup stage
./virtualizor-server-setup.sh --status
```

## 🔐 SSH Tunnel Setup - Multi-Server Management

The script automatically generates SSH keys and creates tunnel services for **multiple guest servers connecting to one Zabbix server**. Manual key management is required on the monitoring server:

### **One-Time Server Setup** (Configure Once)

1. **Create SSH User** (handles all guest connections):
```bash
# On monitoring server (monitor.cloudgeeks.in)
sudo useradd -r -s /bin/false -m zabbixssh
sudo mkdir -p /home/zabbixssh/.ssh
sudo chmod 700 /home/zabbixssh/.ssh
sudo touch /home/zabbixssh/.ssh/authorized_keys
sudo chmod 600 /home/zabbixssh/.ssh/authorized_keys
sudo chown -R zabbixssh:zabbixssh /home/zabbixssh/
```

2. **Configure SSH Server**:
```bash
# Edit /etc/ssh/sshd_config
Port 20202
AllowUsers zabbixssh
AllowTcpForwarding yes
MaxSessions 100
MaxStartups 50:30:100
sudo systemctl restart sshd
```

### **Per-Guest Server Process** (Repeat for Each Guest)

1. **Get Public Key** (from script output):
   ```bash
   # After running script, key is displayed and saved to:
   cat /root/zabbix_tunnel_public_key.txt
   ```

2. **Add to Monitoring Server** (append, don't overwrite):
   ```bash
   # On monitoring server - APPEND new key
   echo "ssh-rsa AAAAB3... zabbix-tunnel-guest1-20250721" >> /home/zabbixssh/.ssh/authorized_keys
   echo "ssh-rsa AAAAB3... zabbix-tunnel-guest2-20250721" >> /home/zabbixssh/.ssh/authorized_keys
   # ... repeat for each guest server
   ```

3. **Start Guest Tunnel Service**:
   ```bash
   # On each guest server
   systemctl start zabbix-tunnel
   systemctl enable zabbix-tunnel
   ```

4. **Add to Zabbix Web Interface** (each server individually):
   - **Host name**: Unique hostname (guest1, guest2, etc.)
   - **IP address**: `127.0.0.1` (all use tunnel endpoint)
   - **Port**: `10050` (standard for all servers)

### **Scaling to Many Servers**
- ✅ **Same SSH Port**: All guests connect to port 20202
- ✅ **Same SSH User**: All use `zabbixssh` user
- ✅ **Unique Keys**: Each guest has unique SSH key
- ✅ **Individual Tunnels**: Each guest creates separate encrypted tunnel
- ✅ **Single Management**: One authorized_keys file manages all access

## 🛠️ Troubleshooting

### Common Issues

#### Script Won't Continue After Reboot
```bash
# Check systemd service status
systemctl status virtualizor-server-setup.service

# Manual resume
./virtualizor-server-setup.sh --resume-after-reboot
```

#### SSH Tunnel Connection Failed
```bash
# Test SSH connectivity manually
ssh -i /root/.ssh/zabbix_tunnel_key -p 20202 zabbixssh@monitor.cloudgeeks.in

# Check tunnel service logs
journalctl -u zabbix-tunnel --lines 50
```

#### Package Installation Failed
```bash
# Retry from updates stage
./virtualizor-server-setup.sh --stage updates

# Check package manager logs
cat /var/log/apt/history.log  # Ubuntu/Debian
cat /var/log/dnf.log          # RHEL/CentOS
```

### Emergency Recovery
```bash
# Complete cleanup and restart
./virtualizor-server-setup.sh --cleanup
./virtualizor-server-setup.sh
```

## 📚 Documentation

- **[Master Script Guide](docs/virtualizor-master-script.md)** - Comprehensive master script documentation
- **[Virtualizor Integration](docs/installation.md)** - Recipe setup and integration instructions  
- **[SSH Tunnel Usage](docs/usage.md)** - Detailed tunnel configuration and management
- **[Troubleshooting Guide](docs/troubleshooting-guide.md)** - Common issues and solutions

## 🏷️ Supported Systems

- **Ubuntu** 18.04, 20.04, 22.04, 24.04
- **Debian** 10, 11, 12
- **RHEL/CentOS** 7, 8, 9
- **AlmaLinux/Rocky** 8, 9

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add improvement'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Create a Pull Request

## 🆕 Recent Updates (July 2025)

**Script Quality & Reliability Improvements:**

- ✅ **Enhanced Syntax Validation**: Script validates syntax before execution with comprehensive error checking
- ✅ **Variable Consistency**: Fixed unbound variable errors, centralized all configuration variables  
- ✅ **Cross-Platform Compatibility**: Improved AlmaLinux/RHEL support with dynamic configuration detection
- ✅ **Phased Updates Handling**: Ubuntu phased update system properly detected and handled
- ✅ **Error Recovery**: Enhanced graceful handling of missing reboot flags and corrupted states

**Systemd Service & State Management:**

- ✅ **Service Reliability**: Fixed "bad-setting" errors with absolute path resolution
- ✅ **Reboot Persistence**: Improved state file management across system reboots
- ✅ **Service Optimization**: Systemd service only runs when actually needed (with reboot flag)
- ✅ **Smart Recovery**: Automatic detection of completed setups and graceful state recovery
- ✅ **Exit Code Resolution**: Fixed exit code 1 issues with better resume logic

**Package Management & Updates:**

- ✅ **Phased Update Detection**: Automatic detection and handling of Ubuntu's phased update system
- ✅ **Progress Monitoring**: Enhanced background process monitoring with timeout handling
- ✅ **Update Optimization**: Faster package operations with improved dpkg configuration
- ✅ **Interactive Prevention**: Complete elimination of interactive prompts during updates
- ✅ **Kernel Update Handling**: Specialized handling for kernel updates and GRUB configuration

**Zabbix Configuration & Detection:**

- ✅ **Dynamic Config Detection**: Automatic detection of Zabbix configuration file locations
- ✅ **Multi-OS Support**: Works correctly on Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS
- ✅ **Configuration Validation**: Enhanced validation of Zabbix agent configuration
- ✅ **Service Management**: Improved Zabbix agent service startup and configuration

**Customer Privacy & Administrator Access:**

- ✅ **Customer-Friendly Banners**: Server banners show only "Server Ready" without technical details
- ✅ **Administrator Documentation**: Complete SSH key and setup info available in `/root/` files
- ✅ **Banner Persistence**: SSH banners properly updated and maintained across reboots
- ✅ **Access Management**: Clear separation between customer-facing and administrator information

**Quality Assurance Status:**

- Syntax validation: COMPREHENSIVE ✅
- Cross-platform testing: VERIFIED ✅  
- Error handling: ENHANCED ✅
- Package management: OPTIMIZED ✅
- State persistence: ROBUST ✅
- Production readiness: CONFIRMED ✅

## 📞 Support

For issues and questions:

- **GitHub Issues**: [Create an issue](https://github.com/virxpert/zabbix-monitor/issues)
- **Documentation**: Check the `/docs` directory
- **Logs**: Always include relevant log files when reporting issues

