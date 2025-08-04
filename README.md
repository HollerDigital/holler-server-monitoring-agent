# GridPane Manager Backend API

Apple-friendly, App Store-compliant backend service for the GridPane Manager iOS app. This Node.js API handles all privileged server operations, monitoring, and notifications without requiring direct SSH access from the mobile app.

**🚀 MAJOR UPDATE:** Upgraded from Python Flask to Node.js Express for better iOS integration, enhanced security, and improved performance.

## Features

- **System Metrics**: CPU usage, memory usage, disk space, network statistics
- **Service Control**: Restart services (nginx, MySQL, PHP-FPM) via GridPane CLI
- **Cache Management**: Clear site and server-wide cache using GridPane tools
- **REST API**: Secure JWT-authenticated endpoints for iOS app integration
- **GridPane Integration**: Uses official GridPane CLI commands for all operations
- **Systemd Service**: Runs as a background service with automatic startup
- **Real-time Monitoring**: WebSocket support for live metrics (planned)
- **Push Notifications**: Server alerts and status updates (planned)
- **Lightweight**: Minimal resource footprint with Node.js efficiency

## Installation

### Automatic Installation

Run the installation script on your GridPane server:

```bash
cd /tmp
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
chmod +x install.sh
sudo ./install.sh
```

### Manual Installation

1. Install Node.js 18.x LTS:
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
   sudo apt-get install -y nodejs
   ```

2. Create service user and directories:
   ```bash
   sudo useradd --system --shell /bin/false gridpane-manager
   sudo mkdir -p /opt/gridpane-manager /var/log/gridpane-manager /etc/gridpane-manager
   ```

3. Copy application files and install dependencies:
   ```bash
   sudo cp -r . /opt/gridpane-manager/
   cd /opt/gridpane-manager
   sudo -u gridpane-manager npm install --production
   ```

4. Configure environment and start service:
   ```bash
   sudo cp .env.example /etc/gridpane-manager/.env
   sudo systemctl enable gridpane-manager
   sudo systemctl start gridpane-manager
   ```

## Configuration

The backend service runs on port 3000 by default and requires JWT authentication for all endpoints except health checks. Configuration is managed through environment variables in `/etc/gridpane-manager/.env`.

### Environment Variables

```bash
# Server Configuration
PORT=3000
NODE_ENV=production

# Authentication
JWT_SECRET=your-secure-jwt-secret-here
JWT_EXPIRES_IN=24h

# GridPane Integration
GRIDPANE_API_TOKEN=your-gridpane-api-token
GRIDPANE_CLI_PATH=/usr/local/bin/gp

# Monitoring
METRICS_INTERVAL=30000
ALERT_THRESHOLDS_CPU=80
ALERT_THRESHOLDS_MEMORY=85
ALERT_THRESHOLDS_DISK=90
```

## API Endpoints

### Authentication
```bash
# Login with GridPane credentials
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "your-username", "password": "your-password"}'
```

### Health Check (No Auth Required)
```bash
curl http://localhost:3000/api/health
```

### System Metrics (Auth Required)
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/metrics
```

Response format:
```json
{
  "timestamp": "2025-08-04T17:30:00Z",
  "cpu": {
    "usage_percent": 15.2,
    "load_average": [0.5, 0.8, 1.2]
  },
  "memory": {
    "usage_percent": 45.8,
    "total_gb": 16.0,
    "available_gb": 8.7
  },
  "disk": {
    "/": {
      "usage_percent": 67.3,
      "total_gb": 50.0,
      "available_gb": 16.4
    }
  },
  "network": {
    "bytes_sent": 1024000,
    "bytes_recv": 2048000
  }
}
```

### Service Control (Auth Required)
```bash
# Restart nginx
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/services/nginx/restart

# Restart MySQL
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/services/mysql/restart

# Restart PHP-FPM
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/services/php-fpm/restart
```

### Cache Management (Auth Required)
```bash
# Clear all site caches
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/cache/clear-all

# Clear specific site cache
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/cache/clear/example.com
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

## Uninstallation

To remove the backend service:

```bash
# Stop and disable service
sudo systemctl stop gridpane-manager
sudo systemctl disable gridpane-manager

# Remove service files
sudo rm /etc/systemd/system/gridpane-manager.service
sudo systemctl daemon-reload

# Remove application files
sudo rm -rf /opt/gridpane-manager
sudo rm -rf /var/log/gridpane-manager
sudo rm -rf /etc/gridpane-manager

# Remove service user
sudo userdel gridpane-manager
```

## Requirements

- Node.js 18.x LTS or higher
- npm (included with Node.js)
- systemd (for service management)
- GridPane server environment with CLI tools
- Ubuntu/Debian-based system (recommended)

## License

MIT License - see LICENSE file for details.

## Support

For support and issues, please contact Holler Digital or create an issue in this repository.
