# Security Configuration Guide

## 🔒 **CRITICAL: Secure Deployment Guidelines**

This guide ensures secure deployment of the Zabbix monitoring system by eliminating hardcoded credentials and using environment-based configuration.

## ⚠️ **Security Requirements**

### **1. Environment Variables (Mandatory)**

**Never use default or hardcoded values in production!**

Create your secure configuration:
```bash
# Copy the template
cp .env.example .env

# Edit with YOUR specific values
nano .env
```

### **2. Secure Configuration Values**

**✅ DO:**
- Use unique, non-predictable SSH usernames
- Use non-standard SSH ports (avoid 22, 2222, 20202)  
- Use your own domain or IP address
- Generate strong SSH keys (RSA 4096-bit or ED25519)

**❌ DON'T:**
- Use example values from documentation
- Use predictable usernames like 'zabbix', 'zabbixssh', 'monitoring'
- Use common ports like 22, 2222, 10050 for SSH tunnels
- Commit .env files to version control

### **3. Required Environment Variables**

```bash
# Your Zabbix monitoring server (REQUIRED)
ZABBIX_SERVER_DOMAIN="your-monitor-server.example.com"

# SSH tunnel configuration (REQUIRED)
SSH_TUNNEL_PORT="7832"  # Use random high port
SSH_TUNNEL_USER="mon-agent-prod"  # Use unique username

# Zabbix configuration (OPTIONAL)
ZABBIX_VERSION="6.4"
ZABBIX_SERVER_PORT="10051"
```

### **4. Deployment Security Checks**

Before deploying, verify:
```bash
# Check environment variables are set
echo "Server: $ZABBIX_SERVER_DOMAIN"
echo "SSH Port: $SSH_TUNNEL_PORT" 
echo "SSH User: $SSH_TUNNEL_USER"

# Verify no default values are used
if [[ "$ZABBIX_SERVER_DOMAIN" == *"example.com"* ]]; then
    echo "ERROR: Using example domain - update .env file!"
    exit 1
fi

# Run deployment with environment
./virtualizor-server-setup.sh
```

## 🛡️ **Infrastructure Security**

### **SSH Tunnel Security**

1. **Unique SSH Keys per Server**
   - Each guest server generates its own SSH key pair
   - No shared or reused SSH keys across servers

2. **Non-Standard Ports**
   - Avoid common SSH ports (22, 2222, 10022, 20202)
   - Use random high ports (1024-65535)

3. **Dedicated SSH Users**
   - Create service-specific SSH users for monitoring
   - Avoid generic usernames ('zabbix', 'monitoring', 'ssh')

### **Network Security**

1. **Firewall Configuration**
   - Only allow SSH tunnel connections from specific IPs
   - Block direct Zabbix agent connections (force tunnel usage)

2. **DNS Security**
   - Use proper DNS configuration for monitoring server
   - Consider using private DNS for internal monitoring

## 🔧 **Production Deployment**

### **Step 1: Environment Setup**
```bash
# Create secure .env configuration
export ZABBIX_SERVER_DOMAIN="monitor-prod.yourcompany.com"
export SSH_TUNNEL_PORT="7832"
export SSH_TUNNEL_USER="monitoring-agent-prod"

# Verify configuration
env | grep -E "(ZABBIX|SSH)"
```

### **Step 2: Deploy with Environment**
```bash
# Deploy using environment variables
./virtualizor-server-setup.sh

# Or use Virtualizor recipe with environment
ZABBIX_SERVER_DOMAIN="your-server.com" curl -fsSL \
  https://raw.githubusercontent.com/virxpert/zabbix-monitor/main/virtualizor-recipes/direct-download-recipe.sh | bash
```

### **Step 3: Post-Deployment Verification**
```bash
# Check SSH tunnel configuration
ssh -i /root/.ssh/zabbix_tunnel_key -p $SSH_TUNNEL_PORT $SSH_TUNNEL_USER@$ZABBIX_SERVER_DOMAIN

# Verify Zabbix agent connection
zabbix_agentd -t system.hostname

# Check service status
systemctl status zabbix-agent
```

## 🚨 **Security Incident Response**

If default values were used in production:

### **Immediate Actions:**
1. **Change SSH Configuration**
   ```bash
   # Generate new SSH keys
   ssh-keygen -t ed25519 -f /root/.ssh/new_zabbix_key
   
   # Update tunnel configuration with new port/user
   # Update Zabbix server authorized_keys
   ```

2. **Update Environment**
   ```bash
   # Set new secure values
   export SSH_TUNNEL_PORT="NEW_RANDOM_PORT"
   export SSH_TUNNEL_USER="NEW_UNIQUE_USERNAME"
   
   # Re-run configuration
   ./virtualizor-server-setup.sh --reconfigure
   ```

3. **Monitor for Unauthorized Access**
   - Check SSH logs for unauthorized connection attempts
   - Review Zabbix server logs for unexpected agents
   - Monitor system logs for suspicious activity

## 📋 **Security Compliance Checklist**

- [ ] Environment variables configured with unique values
- [ ] No default/example values used in production
- [ ] SSH ports changed from defaults (22, 2222, 20202)
- [ ] SSH usernames are non-predictable
- [ ] SSH keys are unique per server
- [ ] .env file excluded from version control
- [ ] DNS configuration verified for monitoring server
- [ ] Firewall rules restrict access to tunnel endpoints
- [ ] Monitoring server access controls configured
- [ ] Security incident response plan documented

**Remember: Security through obscurity is NOT security. Use proper authentication, authorization, and encryption.**
