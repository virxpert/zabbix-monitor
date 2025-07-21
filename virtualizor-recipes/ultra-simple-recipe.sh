#!/bin/bash
# Ultra-Simple Recipe - AlmaLinux 10 Compatible
wget -O /tmp/virtualizor-server-setup.sh https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/scripts/virtualizor-server-setup.sh && \
bash /tmp/virtualizor-server-setup.sh \
    --ssh-host "monitor.somehost.com" \
    --ssh-port "22" \
    --ssh-user "zabbixuser" \
    --zabbix-version "6.4"
