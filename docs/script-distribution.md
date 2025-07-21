# Script Distribution Guide

## Issue: Repository Access

The repository `https://github.com/virxpert/zabbix-monitor` returns 404 errors when accessing raw files, indicating it may be private or have restricted access.

## Recent Fix: Shell Compatibility

**Fixed**: Syntax error "redirection unexpected" on line 62
- **Problem**: Process substitution `>(tee ...)` not supported in all shells  
- **Solution**: Replaced with compatible named pipe approach
- **Added**: Shell compatibility check to ensure bash execution

**Execution Requirements:**
```bash
# Ensure script runs with bash (not sh)
bash virtualizor-server-setup.sh

# Or make executable and ensure bash shebang works
chmod +x virtualizor-server-setup.sh
./virtualizor-server-setup.sh
```

## Distribution Solutions

### Option 1: Make Repository Public

**Steps:**
1. Go to GitHub repository settings
2. Navigate to General → Danger Zone  
3. Change visibility to "Public"
4. Raw file URL will work: `https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh`

### Option 2: Private Repository with Authentication

**For authenticated access:**
```bash
# Using GitHub token
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/virxpert/zabbix-monitor/contents/scripts/virtualizor-server-setup.sh \
  | jq -r '.content' | base64 -d > virtualizor-server-setup.sh
```

### Option 3: Alternative Distribution Methods

**Direct File Sharing:**
```bash
# Copy script to your web server
scp scripts/virtualizor-server-setup.sh user@yourserver:/var/www/html/
# Access: https://yourserver.com/virtualizor-server-setup.sh
```

**Virtualizor Recipe Integration:**
```bash
# Embed directly in Virtualizor recipe (recommended)
# Copy entire script content into recipe execution section
```

**Package Distribution:**
```bash
# Create downloadable archive
tar -czf zabbix-monitor-scripts.tar.gz scripts/ docs/
# Host on your infrastructure
```

## Recommended Approach for Virtualizor

**Best Practice**: Embed the script directly in Virtualizor recipes rather than downloading from external URLs:

1. Copy `scripts/virtualizor-server-setup.sh` content
2. Paste directly into Virtualizor recipe execution field  
3. No external dependencies or network access required
4. Guaranteed availability during server provisioning

**Recipe Template:**
```bash
#!/bin/bash
# Embedded Zabbix Monitoring Setup
# Generated from: https://github.com/virxpert/zabbix-monitor

set -euo pipefail

# [ENTIRE SCRIPT CONTENT EMBEDDED HERE]
# ... rest of virtualizor-server-setup.sh code ...
```

This approach eliminates network dependencies and ensures reliable execution during automated server provisioning.
