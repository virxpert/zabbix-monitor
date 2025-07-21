# Archive Directory

This directory contains legacy scripts, development artifacts, and documentation that have been superseded by the unified **Virtualizor Server Setup** approach.

## Directory Structure

### `/legacy-scripts` - Superseded Scripts
Individual scripts that have been replaced by the master script `virtualizor-server-setup.sh`. Kept for reference purposes only.

**Archived Files:**
- `configure-zabbix.sh` - Standalone Zabbix configuration with SSH tunnel (superseded by master script)
- `create-secure-tunnel.sh` - SSH tunnel creation (superseded by master script)
- `install-zabbix-agent.sh` - Standalone Zabbix installation (superseded by master script) 
- `install_zabbix_agent_virtualizor.sh` - Virtualizor-specific installation (superseded by master script)
- `monitor-logs.sh` - Log monitoring utilities (reference implementation)
- `monitor-ports.sh` - Port monitoring utilities (reference implementation)

### `/tests` - Development Test Scripts
Test scripts that were designed for development validation.

### `/development-artifacts` - Development Status Documents
Development and status documents created during repository improvement process:

**Root-Level Development Files (Moved July 21, 2025):**
- `FINAL_STATUS_RESOLVED.md` - Final implementation status summary
- `IMPLEMENTATION_COMPLETE.md` - Complete implementation documentation  
- `REPOSITORY_SECURITY_STATUS.md` - Security audit status report
- `SECURITY_AUDIT_REPORT.md` - Detailed security audit findings

### `/legacy-documentation` - Superseded Documentation  
Documentation that has been replaced by current user guides:

**Legacy Documentation Files (Moved July 21, 2025):**
- `legacy-development-guide.md` - Historical development information
- `MULTI_OS_STATUS.md` - Multi-OS compatibility status (now in main docs)
- `REPOSITORY-STATUS.md` - Repository status report (superseded)
- `security-configuration.md` - Security configuration (now integrated in main guides)
- `ssh-key-access-solution.md` - SSH key access solutions (replaced by current guides)
- `script-distribution.md` - Script distribution strategies (superseded by recipe approach)
- `homelab-nat-configuration.md` - NAT configuration for home labs (specialized use case)

### `/troubleshooting-artifacts` - Development Troubleshooting
Troubleshooting documents created during development phases:

**Troubleshooting Development Files (Moved July 21, 2025):**
- `REBOOT_FIX_SUMMARY.md` - Reboot handling fix summary  
- `SYNTAX-FIX-REPORT.md` - Syntax error resolution report
- `TROUBLESHOOTING-EXIT-CODE-1.md` - Exit code troubleshooting documentation

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
