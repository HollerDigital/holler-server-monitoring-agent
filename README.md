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

## Quick Deployment Guide

### Deploy to New Server (Recommended)

For each new GridPane server, run this one-liner as root:

```bash
curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash
```

**OR** use the manual clone method:

```bash
cd /tmp
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
chmod +x install.sh
sudo ./install.sh
```

### Post-Installation Steps

1. **Set your API key** (replace `YOUR_SECURE_API_KEY` with your actual key):
   ```bash
   sudo systemctl edit gridpane-manager --full
   # Add this line in the [Service] section:
   # Environment="API_KEY=YOUR_SECURE_API_KEY"
   ```

2. **Restart the service**:
   ```bash
   sudo systemctl restart gridpane-manager
   ```

3. **Verify installation**:
   ```bash
   # Check service status
   sudo systemctl status gridpane-manager
   
   # Test health endpoint
   curl http://localhost:3000/health
   
   # Test authenticated endpoint
   curl -H "X-API-Key: YOUR_SECURE_API_KEY" http://localhost:3000/api/metrics
   ```

4. **Open firewall** (if needed for external access):
   ```bash
   sudo ufw allow 3000/tcp
   ```

### Multi-Server Deployment

To deploy to multiple servers efficiently:

1. **Create a deployment script** (`deploy-to-servers.sh`):
   ```bash
   #!/bin/bash
   
   # List of your GridPane server IPs
   SERVERS=(
       "45.77.226.198"
       "your.second.server.ip"
       "your.third.server.ip"
   )
   
   API_KEY="YOUR_SECURE_API_KEY_HERE"
   
   for server in "${SERVERS[@]}"; do
       echo "🚀 Deploying to $server..."
       
       # Deploy the agent
       ssh root@$server 'curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | bash'
       
       # Set API key
       ssh root@$server "systemctl edit gridpane-manager --full" <<EOF
   [Unit]
   Description=GridPane Manager Backend API
   After=network.target
   
   [Service]
   Type=simple
   User=holler-app-test
   Group=holler-app-test
   WorkingDirectory=/opt/gridpane-manager
   ExecStart=/usr/bin/node src/server.js
   Restart=always
   RestartSec=10
   Environment="NODE_ENV=production"
   Environment="PORT=3000"
   Environment="API_KEY=$API_KEY"
   StandardOutput=journal
   StandardError=journal
   SyslogIdentifier=gridpane-manager
   
   [Install]
   WantedBy=multi-user.target
   EOF
       
       # Restart service
       ssh root@$server 'systemctl restart gridpane-manager'
       
       # Verify deployment
       echo "✅ Testing $server..."
       ssh root@$server 'curl -s http://localhost:3000/health | jq .'
       
       echo "✅ $server deployment complete!"
       echo "---"
   done
   
   echo "🎉 All servers deployed successfully!"
   ```

2. **Make it executable and run**:
   ```bash
   chmod +x deploy-to-servers.sh
   ./deploy-to-servers.sh
   ```

### CloudFlare Setup (Production)

For production deployment with SSL/HTTPS (required for App Store compliance):

#### 1. Domain Setup

Create subdomains for each server in CloudFlare:
- `server1-api.yourdomain.com` → Server 1 IP
- `server2-api.yourdomain.com` → Server 2 IP
- `server3-api.yourdomain.com` → Server 3 IP

#### 2. CloudFlare DNS Records

Add A records for each server:
```
Type: A
Name: server1-api
Content: 45.77.226.198
Proxy: ✅ Proxied (Orange Cloud)
TTL: Auto
```

#### 3. CloudFlare SSL Settings

1. **SSL/TLS Mode**: Set to "Full (strict)" or "Full"
2. **Always Use HTTPS**: Enable
3. **Minimum TLS Version**: 1.2
4. **Automatic HTTPS Rewrites**: Enable

#### 4. Nginx Reverse Proxy Setup

On each GridPane server, create an Nginx configuration:

```bash
# Create Nginx site configuration
sudo nano /etc/nginx/sites-available/gridpane-manager-api
```

Add this configuration:
```nginx
server {
    listen 80;
    listen 443 ssl http2;
    server_name server1-api.yourdomain.com;  # Change for each server
    
    # SSL Configuration (GridPane auto-manages SSL)
    ssl_certificate /etc/letsencrypt/live/server1-api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/server1-api.yourdomain.com/privkey.pem;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint (no auth required)
    location /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }
}
```

#### 5. Enable the Site

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/gridpane-manager-api /etc/nginx/sites-enabled/

# Test Nginx configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

#### 6. SSL Certificate Setup

Use GridPane's built-in SSL management or manually with Let's Encrypt:

```bash
# Using GridPane CLI (recommended)
gp site server1-api.yourdomain.com -ssl-enable

# OR manually with certbot
sudo certbot --nginx -d server1-api.yourdomain.com
```

#### 7. Update iOS App Configuration

Update your iOS app to use HTTPS endpoints:
```swift
// In BackendAPIService.swift
let baseURL = "https://server1-api.yourdomain.com"
```

#### 8. CloudFlare Security Rules (Optional)

Add security rules in CloudFlare:

1. **Rate Limiting**: 100 requests per minute per IP
2. **Geographic Restrictions**: Block unwanted countries
3. **Bot Fight Mode**: Enable
4. **DDoS Protection**: Automatic

#### 9. Monitoring and Alerts

Set up CloudFlare monitoring:
- **Health Checks**: Monitor `/health` endpoint
- **Email Alerts**: Notify on downtime
- **Analytics**: Track API usage

#### 10. Testing Production Setup

```bash
# Test HTTPS endpoint
curl https://server1-api.yourdomain.com/health

# Test authenticated endpoint
curl -H "X-API-Key: YOUR_API_KEY" \
  https://server1-api.yourdomain.com/api/metrics

# Test SSL grade
ssl-checker server1-api.yourdomain.com
```

## Installation

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

The backend service runs on port 3000 by default and uses API key authentication for all endpoints except health checks. Configuration is managed through environment variables in `/etc/gridpane-manager/.env`.

### Environment Variables

```bash
# Server Configuration
PORT=3000
NODE_ENV=production

# Authentication
API_KEY=your-secure-api-key-here

# GridPane Integration
GRIDPANE_CLI_PATH=/usr/local/bin/gp

# Monitoring
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
