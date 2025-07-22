# Repository Structure (Updated July 21, 2025)

## 📁 Active Project Structure

```text
zabbix-monitor/
├── 📝 README.md                              # Main project documentation
├── 🔧 scripts/
│   ├── virtualizor-server-setup.sh          # 🎯 MASTER SCRIPT (main provisioning)
│   └── virtualizor-recipe-diagnostic.sh     # 🔍 Diagnostic and troubleshooting tool
├── 📊 virtualizor-recipes/
│   ├── ultra-simple-recipe.sh               # ⚡ Ultra-minimal 6-line recipe
│   ├── smart-dynamic-recipe.sh              # 🧠 Configuration validation recipe
│   ├── direct-download-recipe.sh            # 📥 Direct download pattern
│   ├── embedded-script-recipe.sh            # 📦 Self-contained full script
│   ├── cloud-init-compatible-recipe.sh      # ☁️ Cloud-init integration
│   └── README.md                             # Recipe documentation
├── 📚 docs/
│   ├── installation.md                      # Installation and setup guide
│   ├── troubleshooting-guide.md            # Comprehensive troubleshooting
│   ├── zabbix-server-configuration.md      # Server-side setup instructions
│   ├── quality-assurance.md               # QA features and testing
│   └── [other documentation files]
├── 🛠️ fix-ssh-tunnel-hostname.sh           # 🔧 Quick fix for existing servers
├── 🗂️ archive/                             # Archived development artifacts
└── ⚙️ .github/copilot-instructions.md      # Development guidelines
```

## 🎯 Essential Files for Users

### **For Virtualizor Administrators:**

1. **`scripts/virtualizor-server-setup.sh`** - The main script that does everything
2. **`virtualizor-recipes/ultra-simple-recipe.sh`** - Simplest recipe for Virtualizor
3. **`docs/installation.md`** - Setup instructions
4. **`docs/troubleshooting-guide.md`** - Problem resolution

### **For Current Server Fixes:**

- **`fix-ssh-tunnel-hostname.sh`** - Fixes hostname issues on existing deployments

## 🗄️ Archived Content

All development artifacts, legacy scripts, and troubleshooting reports have been organized in `/archive/`:

- `archive/development-artifacts/` - Status reports and implementation summaries
- `archive/legacy-scripts/` - Old individual scripts (superseded by master script)
- `archive/troubleshooting-artifacts/` - Historical problem resolution reports

## 🧹 Repository Status

✅ **Clean**: Non-essential files archived
✅ **Current**: All scripts updated with latest fixes (AlmaLinux 10, SSH hostname)
✅ **Tested**: Master script handles complete provisioning lifecycle
✅ **Documented**: Comprehensive guides available

Last cleanup: July 21, 2025
