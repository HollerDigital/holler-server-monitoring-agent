# Server Agent - Minimal HTTPS API for Server Control

Secure, lightweight server agent that provides a minimal HTTPS API for server control operations. Designed as part of a distributed architecture where iOS apps communicate with a central orchestrator, which then securely relays commands to individual server agents.

**🔐 SECURITY-FIRST DESIGN:** Uses D-Bus for direct systemd communication, eliminating the need for sudo or shell command execution.

## Architecture Overview

This server agent is designed for a **centralized orchestrator architecture**:

- **iOS App** ↔ **Central Orchestrator** ↔ **Server Agents** (this component)
- **No direct SSH** required from mobile devices
- **Secure communication** via private networks, VPN, or Cloudflare Tunnels
- **Minimal attack surface** with localhost-only binding by default

## Features

- **🔒 Secure Service Control**: Direct D-Bus communication with systemd (no sudo required)
- **🎯 Minimal API Surface**: Only essential endpoints for server management
- **🛡️ Security Hardened**: Dedicated system user with locked-down permissions
- **📊 Service Discovery**: Automatic detection of controllable services
- **🔧 Service Management**: Start, stop, restart, reload services (nginx, mysql, php-fpm, redis, etc.)
- **💾 Cache Operations**: GridPane CLI integration for cache clearing
- **📝 Comprehensive Logging**: Full audit trail with request tracking
- **⚡ High Performance**: D-Bus communication eliminates shell command overhead
- **🚀 One-Line Install**: Fully automated setup with security configuration

## Installation

### Quick Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install-agent.sh | sudo bash
```

This one-line installer will:
- ✅ Install Node.js dependencies including D-Bus library
- ✅ Create `svc-control` system user with minimal privileges
- ✅ Configure D-Bus permissions for secure systemd communication
- ✅ Set up systemd service with security hardening
- ✅ Generate secure API key automatically
- ✅ Start the agent on `127.0.0.1:3001`

### Manual Install

1. Clone the repository:
```bash
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
```

2. Run the installer:
```bash
sudo ./install-agent.sh
```

### Configuration

After installation, the agent configuration is located at:
```bash
/opt/server-agent/.env
```

Key configuration options:
```bash
# Agent Identity
AGENT_ID=agent-$(hostname)
AGENT_NAME=Server Agent - $(hostname)

# Network (localhost-only by default for security)
AGENT_PORT=3001
AGENT_HOST=127.0.0.1

# Security
AGENT_API_KEY=your-generated-api-key
AGENT_ALLOWED_IPS=127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/server-agent/agent.log

# GridPane Integration
GRIDPANE_ENABLED=true
GP_CLI_PATH=/usr/local/bin/gp
```

To modify configuration:
```bash
sudo nano /opt/server-agent/.env
sudo systemctl restart server-agent
```

## API Endpoints

The server agent provides a minimal set of endpoints for server control operations.

### Authentication

All protected endpoints require an API key in the `X-API-Key` header:
```bash
curl -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/endpoint
```

### Public Endpoints (No Authentication)

#### Health Check
```bash
curl http://127.0.0.1:3001/health
```

Response:
```json
{
  "status": "healthy",
  "agent": {
    "id": "agent-hostname",
    "name": "Server Agent - hostname",
    "version": "2.1.0",
    "mode": "agent"
  },
  "timestamp": "2025-08-11T02:20:45.903Z",
  "uptime": 8.421862214
}
```

#### Agent Information
```bash
curl http://127.0.0.1:3001/agent/info
```

### Protected Endpoints (API Key Required)

#### Service Status
Get status of all controllable services:
```bash
curl -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/services/status
```

Response:
```json
{
  "success": true,
  "data": {
    "services": {
      "nginx": { "active": true, "enabled": true, "status": "active" },
      "mysql": { "active": true, "enabled": true, "status": "active" },
      "php8.1-fpm": { "active": true, "enabled": true, "status": "active" }
    },
    "aliases": {
      "web": { "services": ["nginx"], "active": true, "activeServices": ["nginx"] },
      "database": { "services": ["mysql"], "active": true, "activeServices": ["mysql"] }
    },
    "method": "dbus",
    "timestamp": "2025-08-11T02:32:35.133Z"
  }
}
```

#### Service Control
Restart specific services:
```bash
# Restart nginx
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/restart/nginx

# Restart MySQL/MariaDB
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/restart/mysql

# Restart PHP-FPM (auto-detects version)
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/restart/php-fpm

# Restart Redis
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/restart/redis
```

#### Generic Service Control
```bash
# Generic service control: /api/control/service/{action}/{service}
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/service/restart/nginx
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/service/start/redis-server
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/service/stop/memcached
```

#### Cache Operations (GridPane Integration)
```bash
# Clear all site caches
curl -X POST -H "X-API-Key: your-api-key" http://127.0.0.1:3001/api/control/cache/clear

# Clear specific site cache
curl -X POST -H "X-API-Key: your-api-key" -H "Content-Type: application/json" \
  -d '{"site": "example.com"}' http://127.0.0.1:3001/api/control/cache/clear-site
```

## Security Architecture

### D-Bus Communication
The agent uses **D-Bus** for secure communication with systemd, eliminating the need for sudo or shell command execution:

- ✅ **Direct systemd communication** via D-Bus interface
- ✅ **No sudo required** - runs with minimal privileges
- ✅ **No shell command injection** risks
- ✅ **Comprehensive audit logging** with request tracking
- ✅ **Service validation** - only allowed services can be controlled

### System User Security
The agent runs as a dedicated `svc-control` system user with:

- **Minimal privileges** - no shell access by default
- **D-Bus permissions** - only for systemd communication
- **Locked-down sudoers** - only specific systemctl commands (fallback)
- **Isolated environment** - separate user/group from other services

### Network Security
- **Localhost binding** - `127.0.0.1:3001` by default
- **API key authentication** - secure token-based access
- **Rate limiting** - prevents abuse
- **Private network ready** - designed for VPN/tunnel communication

## Service Management

### Supported Services
The agent can control these services via D-Bus:

- **Web Servers**: nginx, apache2
- **Databases**: mysql, mariadb
- **PHP**: php8.1-fpm, php8.2-fpm, php8.3-fpm (auto-detection)
- **Cache**: redis-server, memcached
- **Queue Workers**: supervisor
- **Custom services** can be added to configuration

### Service Aliases
Smart service grouping for easier management:

- **`web`** → nginx, apache2
- **`database`** → mysql, mariadb  
- **`php-fpm`** → php8.1-fpm, php8.2-fpm, php8.3-fpm
- **`cache`** → redis-server, memcached

## Management Commands

### Service Control
```bash
# Check service status
sudo systemctl status server-agent

# View logs
sudo journalctl -u server-agent -f

# Restart agent
sudo systemctl restart server-agent

# Stop agent
sudo systemctl stop server-agent
```

### Configuration Management
```bash
# Edit configuration
sudo nano /opt/server-agent/.env

# View current API key
sudo grep AGENT_API_KEY /opt/server-agent/.env

# Check D-Bus permissions
sudo cat /etc/dbus-1/system.d/server-agent.conf
```

## Requirements

- **Operating System**: Ubuntu/Debian-based Linux distribution
- **Node.js**: 16.x LTS or higher (automatically installed)
- **systemd**: For service management
- **D-Bus**: For secure systemd communication (pre-installed on most systems)
- **Root Access**: Required for installation and system user setup

### Optional Requirements
- **GridPane CLI**: For cache clearing operations (`/usr/local/bin/gp`)
- **nginx/apache2**: For web server control
- **mysql/mariadb**: For database server control
- **php-fpm**: For PHP process management
- **redis/memcached**: For cache server control

## Troubleshooting

### Installation Issues

**Node.js Version Conflicts:**
```bash
# Remove old Node.js versions
sudo apt remove nodejs npm
sudo apt autoremove

# Install Node.js 18.x LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should be v18.x or higher
```

**Permission Errors:**
```bash
# Ensure running as root
sudo su -

# Re-run installation
curl -sSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install-agent.sh | bash
```

### Service Issues

**Agent Won't Start:**
```bash
# Check service status
sudo systemctl status server-agent

# View detailed logs
sudo journalctl -u server-agent -n 50

# Check D-Bus permissions
sudo cat /etc/dbus-1/system.d/server-agent.conf
```

**D-Bus Permission Errors:**
```bash
# Restart D-Bus service
sudo systemctl restart dbus

# Restart agent
sudo systemctl restart server-agent
```

**API Connection Issues:**
```bash
# Verify agent is listening
sudo netstat -tlnp | grep 3001

# Test health endpoint
curl http://127.0.0.1:3001/health

# Check API key
sudo grep AGENT_API_KEY /opt/server-agent/.env
```

## Uninstallation

To completely remove the server agent:

```bash
# Stop and disable service
sudo systemctl stop server-agent
sudo systemctl disable server-agent

# Remove service files
sudo rm -f /etc/systemd/system/server-agent.service
sudo rm -f /etc/dbus-1/system.d/server-agent.conf

# Remove application files
sudo rm -rf /opt/server-agent
sudo rm -rf /var/log/server-agent

# Remove system user
sudo userdel svc-control
sudo groupdel svc-control

# Reload systemd
sudo systemctl daemon-reload
sudo systemctl restart dbus
```

## License

MIT License - see LICENSE file for details.

## Support

For support and issues, please create an issue in this repository.

---

**🔐 Security Note**: This agent is designed for localhost-only operation by default. For production deployments with external access, ensure proper network security (VPN, private networks, or secure tunnels) and consider enabling HTTPS with proper SSL certificates.

METRICS_INTERVAL=30000
ALERT_THRESHOLDS_CPU=80
ALERT_THRESHOLDS_MEMORY=85
ALERT_THRESHOLDS_DISK=90

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/gridpane-manager
```

## API Endpoints

### Authentication
The API uses API key authentication. Include the API key in the `X-API-Key` header for all requests except health checks.

### Health Check (No Auth Required)
```bash
curl https://your-server.com/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2025-08-04T21:43:15.669Z",
  "version": "2.0.0",
  "service": "GridPane Manager Backend API"
}
```

### System Metrics (API Key Required)
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
  https://your-server.com/api/metrics
```

Response format:
```json
{
  "timestamp": "2025-08-04T17:30:00Z",
  "cpu": {
    "usage": 15.2,
    "cores": 4
  },
  "memory": {
    "usage": 45.8,
    "total": 17179869184,
    "free": 9289748480
  },
  "disk": [
    {
      "mount": "/",
      "usage": 67.3,
      "size": 53687091200,
      "available": 17592186044416
    }
  ],
  "load": {
    "avg1": 0.5,
    "avg5": 0.8,
    "avg15": 1.2
  },
  "uptime": 86400
}
```

### Service Control (API Key Required)
All service control operations use GridPane CLI commands for proper system integration.

```bash
# Restart nginx using GridPane CLI
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  https://your-server.com/api/control/restart/nginx

# Restart MySQL using GridPane CLI
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  https://your-server.com/api/control/restart/mysql

# Restart entire server (requires confirmation)
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"confirm": "yes"}' \
  https://your-server.com/api/control/restart/server
```

Response format:
```json
{
  "success": true,
  "message": "Nginx restarted successfully using GridPane CLI",
  "output": "nginx: configuration file test successful\nnginx restarted",
  "timestamp": "2025-08-04T21:40:42.381Z"
}
```

### Cache Management (API Key Required)
Cache management uses GridPane CLI commands for proper integration.

```bash
# Clear all caches using GridPane CLI
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  https://your-server.com/api/control/cache/clear

# Clear specific site cache
curl -X POST -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"site": "example.com"}' \
  https://your-server.com/api/control/cache/clear-site
```

Response format:
```json
{
  "success": true,
  "message": "Cache cleared successfully",
  "output": "Redis Cache cleared\nPHP OpCache cleared\nNginx FastCGI Cache cleared",
  "timestamp": "2025-08-04T21:16:27.461Z"
}
```

## Service Management

```bash
# Check service status
sudo systemctl status gridpane-manager

# View logs
sudo journalctl -u gridpane-manager -f

# Restart service
sudo systemctl restart gridpane-manager

# Stop service
sudo systemctl stop gridpane-manager
```

## Uninstallation & Reinstallation

### Quick Uninstall (Recommended)

Use the automated uninstall script for complete removal:

```bash
# Download and run the uninstall script
curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/uninstall.sh | sudo bash
```

**OR** clone and run manually:

```bash
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
sudo bash uninstall.sh
```

#### What the Uninstall Script Removes:
- ✅ **Service**: Stops and disables `gridpane-manager` service
- ✅ **System Files**: Removes systemd service file and reloads daemon
- ✅ **Application**: Deletes `/opt/gridpane-manager` directory
- ✅ **Logs**: Removes `/var/log/gridpane-manager` directory
- ✅ **Configuration**: Option to keep or remove `/etc/gridpane-manager`
- ✅ **User Account**: Removes `gridpane-manager` system user
- ✅ **Permissions**: Removes sudo permissions and logrotate config
- ✅ **Cleanup**: Terminates any remaining processes

#### Configuration Preservation

The uninstall script will ask if you want to keep configuration files:
- **Keep Config**: Preserves API keys and settings for easy reinstall
- **Remove Config**: Complete clean removal

### Manual Uninstall

If you prefer manual removal or the script fails:

```bash
# Stop and disable service
sudo systemctl stop gridpane-manager
sudo systemctl disable gridpane-manager

# Remove systemd files
sudo rm -f /etc/systemd/system/gridpane-manager.service
sudo rm -rf /etc/systemd/system/gridpane-manager.service.d
sudo systemctl daemon-reload

# Remove application and data
sudo rm -rf /opt/gridpane-manager
sudo rm -rf /var/log/gridpane-manager
sudo rm -rf /etc/gridpane-manager  # Optional: keep for reinstall

# Remove system configuration
sudo rm -f /etc/logrotate.d/gridpane-manager
sudo rm -f /etc/sudoers.d/gridpane-manager

# Remove service user
sudo userdel gridpane-manager 2>/dev/null || true

# Kill any remaining processes
sudo pkill -f "gridpane-manager" || true
```

### Reinstallation

#### Clean Reinstall

After uninstalling, reinstall with the latest version:

```bash
# Method 1: One-liner (recommended)
curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash

# Method 2: Interactive install
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
sudo bash install.sh
```

#### Reinstall with Preserved Configuration

If you kept configuration during uninstall:

```bash
# The installer will detect existing configuration
curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash

# Your API keys and settings will be automatically restored
```

#### Update/Upgrade Installation

To update to the latest version without losing configuration:

```bash
# Stop the service
sudo systemctl stop gridpane-manager

# Backup configuration (optional safety measure)
sudo cp -r /etc/gridpane-manager /tmp/gridpane-manager-backup

# Remove only application files (keep config)
sudo rm -rf /opt/gridpane-manager

# Reinstall latest version
curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash

# Service will restart automatically with preserved settings
```

### Troubleshooting Uninstall Issues

#### Service Won't Stop
```bash
# Force kill the service
sudo systemctl kill gridpane-manager
sudo pkill -9 -f "gridpane-manager"
```

#### Permission Denied Errors
```bash
# Ensure you're running as root
sudo su -
# Then run uninstall commands
```

#### Files Still Present After Uninstall
```bash
# Force remove any remaining files
sudo find /opt -name "*gridpane-manager*" -exec rm -rf {} + 2>/dev/null || true
sudo find /etc -name "*gridpane-manager*" -exec rm -rf {} + 2>/dev/null || true
sudo find /var -name "*gridpane-manager*" -exec rm -rf {} + 2>/dev/null || true
```

### Migration Between Servers

To move your GridPane Manager setup to a new server:

1. **Export configuration from old server**:
   ```bash
   # Create backup of configuration
   sudo tar -czf gridpane-manager-config.tar.gz -C /etc gridpane-manager
   ```

2. **Transfer to new server**:
   ```bash
   scp gridpane-manager-config.tar.gz root@new-server:/tmp/
   ```

3. **Install on new server**:
   ```bash
   # Install fresh
   curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash
   
   # Stop service and restore config
   sudo systemctl stop gridpane-manager
   sudo rm -rf /etc/gridpane-manager
   sudo tar -xzf /tmp/gridpane-manager-config.tar.gz -C /etc
   sudo systemctl restart gridpane-manager
   ```

4. **Uninstall from old server**:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/uninstall.sh | sudo bash
   ```

### Verification After Reinstall

After any reinstallation, verify everything is working:

```bash
# Check service status
sudo systemctl status gridpane-manager

# Test health endpoint
curl http://localhost:3000/health

# Test authenticated endpoint (replace YOUR_API_KEY)
curl -H "X-API-Key: YOUR_API_KEY" http://localhost:3000/api/monitoring/system

# Check logs for any errors
sudo journalctl -u gridpane-manager --no-pager -n 20
```

## GridPane CLI Integration

This backend service integrates directly with GridPane CLI commands for all system operations, ensuring compatibility with GridPane's security model and best practices.

### Service Management
- **Nginx restart**: Uses `gp ngx -restart` command
- **MySQL restart**: Uses `gp mysql -restart` command
- **Cache clearing**: Uses `gp fix cached` command
- **Site-specific cache**: Uses `gp site {site} cache clear` command

### System User Requirements
For optimal GridPane CLI integration, the backend service should run as root or a properly configured GridPane system user with SSH access enabled:

```bash
# Enable SSH access for a system user (run as root)
gp user {username} -ssh-access true
```

### GridPane CLI Documentation
For complete GridPane CLI reference, see:
- [GP-CLI Quick Reference](https://gridpane.com/kb/gp-cli-quick-reference/)
- [Connect as System User](https://gridpane.com/kb/connect-to-a-gridpane-server-by-ssh-as-a-system-user/)
- [GridPane CLI Basics](https://gridpane.com/kb/getting-to-know-the-command-line-linux-cli-basics/)

## Requirements

- **GridPane Server**: Must be a GridPane-managed server with CLI tools installed
- **Node.js**: 18.x LTS or higher
- **npm**: Included with Node.js
- **systemd**: For service management
- **Operating System**: Ubuntu/Debian-based system (recommended)
- **GridPane CLI**: `/usr/local/bin/gp` must be available and functional
- **System Privileges**: Service should run as root for full GridPane CLI access

## License

MIT License - see LICENSE file for details.

## Support

For support and issues, please contact Holler Digital or create an issue in this repository.
