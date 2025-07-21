#!/bin/bash
# Test AlmaLinux 10 compatibility fix

# Simulate AlmaLinux 10 environment
ID="almalinux"
VERSION_ID="10"

# Test the OS detection logic (extracted from main script)
case "$ID" in
    rhel|centos|almalinux|rocky)
        OS_FAMILY="rhel"
        OS_ID="$ID"
        OS_VERSION="${VERSION_ID%%.*}"
        
        # AlmaLinux 10 compatibility: use RHEL 9 packages (el10 packages don't exist yet)
        if [[ "$ID" == "almalinux" && "$OS_VERSION" == "10" ]]; then
            echo "AlmaLinux 10 detected - using RHEL 9 packages for Zabbix compatibility"
            OS_VERSION="9"
        fi
        ;;
esac

echo "Test Results:"
echo "  OS_ID: $OS_ID"
echo "  Original VERSION_ID: $VERSION_ID"  
echo "  Final OS_VERSION: $OS_VERSION (should be 9 for AlmaLinux 10)"
echo "  OS_FAMILY: $OS_FAMILY"

# Test the repository URL construction
zabbix_version="6.4"
repo_url="https://repo.zabbix.com/zabbix/${zabbix_version}/rhel/${OS_VERSION}/x86_64/zabbix-release-${zabbix_version}-1.el${OS_VERSION}.noarch.rpm"
echo "  Repository URL: $repo_url"

# Verify it points to el9 instead of el10
if [[ "$repo_url" == *"el9"* ]]; then
    echo "✅ SUCCESS: AlmaLinux 10 compatibility fix working - using el9 packages"
else
    echo "❌ FAILED: Still trying to use el10 packages"
fi
