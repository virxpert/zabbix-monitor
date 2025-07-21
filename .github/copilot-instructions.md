# Copilot Instructions for Zabbix Monitor

## Project Overview
This is a Zabbix monitoring solution project designed to provide comprehensive infrastructure monitoring capabilities. The project follows a modular architecture with clear separation between monitoring configurations, custom scripts, and data processing components.

## Architecture & Components

### Core Structure
- **`/templates/`** - Zabbix template definitions (XML format) for different service types
- **`/scripts/`** - Custom monitoring scripts and data collection tools
- **`/discovery/`** - Auto-discovery scripts for dynamic host/service detection  
- **`/dashboards/`** - Grafana dashboard configurations and Zabbix screen exports
- **`/config/`** - Configuration files for agents, proxies, and server settings
- **`/docs/`** - Deployment guides, troubleshooting, and API documentation

### Key Patterns
- Template naming: `zbx_template_[service]_[version].xml` 
- Script naming: `[service]_[metric].py|sh` with standardized parameter handling
- All scripts use `/usr/local/bin/zabbix-scripts/` prefix for absolute paths
- Discovery scripts return JSON format following Zabbix LLD macros: `{#MACRO}`

## Development Workflows

### Template Development
```bash
# Test template import
zabbix_cli template import templates/zbx_template_app_v1.0.xml
# Validate template syntax
xmllint --noout templates/*.xml
```

### Script Testing
- All monitoring scripts must handle `-t` flag for test mode
- Use `zabbix_sender` for testing metric submission
- Include error handling for network timeouts and API failures

### Configuration Management  
- Use `zabbix_agentd.conf.d/` directory structure for modular agent configs
- Environment-specific settings via `${ENV}` variable substitution
- Proxy configurations inherit from `zabbix_proxy.conf.template`

## Integration Points

### Zabbix API Usage
- Authentication via `ZBX_AUTH_TOKEN` environment variable
- Rate limiting: max 10 requests/second per API endpoint
- Use bulk operations for items/triggers creation (items.create with array)

### External Dependencies
- **Grafana**: Dashboard sync via provisioning configs in `/dashboards/grafana/`
- **SNMP**: MIB files stored in `/mibs/` with dependency mapping in `mib_deps.json`
- **Database**: Custom metrics stored in `zabbix.custom_metrics` table

### Data Flow
1. Agents/Scripts → Zabbix Server → Database
2. Templates define items → Triggers evaluate → Actions execute
3. Historical data → Trends calculation → Dashboard visualization

## Project Conventions

### Monitoring Item Keys
- Format: `[service].[metric][.parameter]`
- Examples: `mysql.queries.per_second`, `apache.workers.idle`
- Custom parameters use bracket notation: `log.error.count[/var/log/app.log]`

### Trigger Expressions
- Use functions: `avg()`, `last()`, `nodata()` with appropriate time periods
- Severity mapping: 0=Not classified, 1=Information, 2=Warning, 3=Average, 4=High, 5=Disaster
- Include recovery expressions for all problem triggers

### File Organization
- Group related templates by technology (linux/, windows/, network/, databases/)
- Version control: use semantic versioning for templates (v1.0.0)
- Change logs in template descriptions field

## Debugging & Troubleshooting

### Log Locations
- Zabbix server: `/var/log/zabbix/zabbix_server.log`
- Agent logs: `/var/log/zabbix/zabbix_agentd.log`
- Custom script logs: `/var/log/zabbix-scripts/[script-name].log`

### Common Issues
- Permission errors: scripts need zabbix user execution rights
- Timeout issues: increase `Timeout` in agent config for long-running scripts
- Data collection gaps: check network connectivity and firewall rules

### Testing Commands
```bash
# Test agent connectivity
zabbix_get -s [host] -k [item_key]
# Test script locally  
sudo -u zabbix /usr/local/bin/zabbix-scripts/[script].py -t
# Validate configuration
zabbix_agentd -t
```

When developing new components, always consider scalability (10k+ hosts), error handling, and documentation. Follow the established patterns for consistency and maintainability.
