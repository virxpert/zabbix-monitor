# Archive Directory

This directory contains legacy scripts and files that have been superseded by the unified **Virtualizor Server Setup** approach.

## Legacy Scripts (`/legacy-scripts`)

These individual scripts are **legacy** and have been replaced by the master script `virtualizor-server-setup.sh`. They are kept for reference purposes only.

### Archived Files:
- `configure-zabbix.sh` - Standalone Zabbix configuration with SSH tunnel (superseded by master script)
- `create-secure-tunnel.sh` - SSH tunnel creation (superseded by master script)
- `install-zabbix-agent.sh` - Standalone Zabbix installation (superseded by master script) 
- `install_zabbix_agent_virtualizor.sh` - Virtualizor-specific installation (superseded by master script)
- `monitor-logs.sh` - Log monitoring utilities (reference implementation)
- `monitor-ports.sh` - Port monitoring utilities (reference implementation)

## Tests (`/tests`)

Test scripts that were designed for development validation.

### Archived Files:
- `test-virtualizor-server-setup.sh` - Test suite for master script (Windows development incompatible)

## Migration Notes

### ✅ Current Production Setup
**Use only these scripts for Virtualizor provisioning:**

1. **`scripts/virtualizor-server-setup.sh`** - Master provisioning script with:
   - Complete server lifecycle management
   - Reboot persistence
   - Stage-based execution
   - Everything Cloud Solutions branding

2. **`scripts/configure-zabbix.sh`** - Enhanced SSH tunnel configuration with:
   - Automatic user creation on remote servers
   - SSH key management
   - Tunnel service setup

### ❌ Deprecated Approach
Do not use individual legacy scripts for new deployments. They lack:
- Reboot persistence
- Conflict prevention
- Unified state management
- Company-specific branding

## Archive Date
Created: 2025-07-21

## Restoration
If you need to restore any archived script:
```bash
# Example: Restore monitor-logs.sh
cp archive/legacy-scripts/monitor-logs.sh scripts/
```

**Note**: Restored legacy scripts may require updates to work with current infrastructure.
