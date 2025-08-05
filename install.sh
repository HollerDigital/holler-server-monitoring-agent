#!/bin/bash

# GridPane Manager Backend Installation Script
# Clean version without syntax errors

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="gridpane-manager"
SERVICE_USER="gridpane-manager"
INSTALL_DIR="/opt/gridpane-manager"
CONFIG_DIR="/etc/gridpane-manager"
LOG_DIR="/var/log/gridpane-manager"

echo "GridPane Manager Backend Installation"
echo "======================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check Node.js installation
if command -v node &> /dev/null; then
    CURRENT_NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    echo -e "${GREEN}Found Node.js v$(node --version)${NC}"
    
    if [ "$CURRENT_NODE_VERSION" -lt 16 ]; then
        echo -e "${YELLOW}Node.js version 16 or higher required. Installing Node.js 18.x...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        apt-get install -y nodejs
    fi
else
    echo -e "${YELLOW}Node.js not found. Installing Node.js 18.x...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    apt-get install -y nodejs
fi

if ! command -v node &> /dev/null; then
    echo -e "${RED}Failed to install Node.js${NC}"
    exit 1
fi

NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 16 ]; then
    echo -e "${RED}Node.js version 16 or higher is required, but found version $NODE_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}Node.js $(node --version) found${NC}"

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Create service user
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating service user: $SERVICE_USER${NC}"
    if useradd --system --shell /bin/false --no-create-home "$SERVICE_USER"; then
        echo -e "${GREEN}Service user created successfully${NC}"
    else
        echo -e "${RED}Failed to create service user${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Service user $SERVICE_USER already exists${NC}"
fi

if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${RED}Service user $SERVICE_USER does not exist${NC}"
    exit 1
fi

USER_GROUP=$(id -gn "$SERVICE_USER" 2>/dev/null)
if [ -z "$USER_GROUP" ]; then
    echo -e "${RED}Cannot determine primary group for user $SERVICE_USER${NC}"
    exit 1
fi

echo -e "${GREEN}User $SERVICE_USER primary group: $USER_GROUP${NC}"

# Set permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R "$SERVICE_USER:$USER_GROUP" "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Install application files
echo -e "${YELLOW}Installing application files...${NC}"
cd "$INSTALL_DIR"

if [ -f "package.json" ]; then
    echo -e "${GREEN}Found existing installation${NC}"
else
    echo -e "${YELLOW}Cloning repository...${NC}"
    git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git .
    if [ ! -f "package.json" ]; then
        echo -e "${RED}Failed to clone repository${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Installing Node.js dependencies...${NC}"
sudo -u "$SERVICE_USER" npm install --production

# Interactive configuration
if [ -t 0 ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}                    GridPane Manager Server Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${YELLOW}Configure your server for SSL/HTTPS access via CloudFlare.${NC}"
    echo
    
    # Server ID Configuration
    echo -e "${GREEN}Step 1: Server ID${NC}"
    echo -e "This unique identifier will be used in your monitor domain URL."
    echo
    read -p "$(echo -e "${YELLOW}Enter Server ID (e.g., web-server-01): ${NC}")" SERVER_ID
    
    if [ -z "$SERVER_ID" ]; then
        DEFAULT_SERVER_ID=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
        if [ -n "$DEFAULT_SERVER_ID" ]; then
            SERVER_ID="$DEFAULT_SERVER_ID"
            echo -e "${BLUE}Using hostname-based Server ID: ${YELLOW}$SERVER_ID${NC}"
        else
            SERVER_ID="gridpane-server-$(date +%s | tail -c 5)"
            echo -e "${BLUE}Generated random Server ID: ${YELLOW}$SERVER_ID${NC}"
        fi
    fi
    
    echo
    
    # Monitor Domain Configuration
    echo -e "${GREEN}Step 2: Monitor Domain (Optional)${NC}"
    echo -e "Configure a custom domain for SSL access via CloudFlare."
    echo
    read -p "$(echo -e "${YELLOW}Enter Monitor Domain (e.g., hollerdigital.dev) or press Enter to skip: ${NC}")" MONITOR_DOMAIN
    
    if [ -n "$MONITOR_DOMAIN" ]; then
        echo -e "${GREEN}✓ Monitor Domain configured: ${BLUE}$MONITOR_DOMAIN${NC}"
        echo -e "${YELLOW}Your backend endpoint will be: ${BLUE}https://$SERVER_ID.$MONITOR_DOMAIN${NC}"
    else
        echo -e "${BLUE}Skipping monitor domain setup. Backend will use HTTP on port 3000.${NC}"
    fi
    
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# Create environment file
if [ ! -f "$CONFIG_DIR/.env" ]; then
    echo -e "${YELLOW}Creating environment configuration...${NC}"
    cp .env.example "$CONFIG_DIR/.env"
    
    # Generate random JWT secret
    JWT_SECRET=$(openssl rand -hex 32)
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" "$CONFIG_DIR/.env"
    
    # Generate API key
    if [ -z "$USER_API_KEY" ]; then
        API_KEY=$(openssl rand -hex 32)
        echo -e "${YELLOW}Generated API key for backend authentication${NC}"
    else
        API_KEY="$USER_API_KEY"
        echo -e "${GREEN}Using provided API key${NC}"
    fi
    
    sed -i "s|API_KEY=.*|API_KEY=$API_KEY|" "$CONFIG_DIR/.env"
    sed -i "s|GRIDPANE_API_KEY=.*|GRIDPANE_API_KEY=$API_KEY|" "$CONFIG_DIR/.env"
    
    if [ -n "$SERVER_ID" ]; then
        sed -i "s|SERVER_ID=.*|SERVER_ID=$SERVER_ID|" "$CONFIG_DIR/.env"
    fi
    
    if [ -n "$MONITOR_DOMAIN" ]; then
        sed -i "s|MONITOR_DOMAIN=.*|MONITOR_DOMAIN=$MONITOR_DOMAIN|" "$CONFIG_DIR/.env"
        sed -i "s|BACKEND_URL=.*|BACKEND_URL=https://$SERVER_ID.$MONITOR_DOMAIN|" "$CONFIG_DIR/.env"
    fi
    
    echo -e "${GREEN}Environment file created${NC}"
fi

# Create systemd service file
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/$SERVICE_NAME.service << 'EOF'
[Unit]
Description=GridPane Manager Backend API
After=network.target
Wants=network.target

[Service]
Type=simple
User=gridpane-manager
Group=users
WorkingDirectory=/opt/gridpane-manager
ExecStart=/usr/bin/node src/server.js
EnvironmentFile=/etc/gridpane-manager/.env
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gridpane-manager

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/gridpane-manager /etc/gridpane-manager
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo -e "${YELLOW}Enabling and starting service...${NC}"
systemctl daemon-reload
systemctl enable $SERVICE_NAME

if systemctl start $SERVICE_NAME; then
    echo -e "${GREEN}Service started successfully${NC}"
else
    echo -e "${RED}Failed to start service${NC}"
    exit 1
fi

# Setup Nginx reverse proxy for CloudFlare integration
if [ -n "$SERVER_ID" ] && [ -n "$MONITOR_DOMAIN" ]; then
    echo
    echo -e "${BLUE}Setting up Nginx reverse proxy...${NC}"
    
    # Add rate limiting to main nginx config if not already present
    if ! grep -q "limit_req_zone.*zone=api" /etc/nginx/nginx.conf; then
        echo "    Adding rate limiting to nginx.conf..."
        sed -i '/http {/a\    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;' /etc/nginx/nginx.conf
    fi
    
    # Create Nginx site configuration
    cat > /etc/nginx/sites-available/gridpane-manager-api << EOF
server {
    listen 80;
    server_name $SERVER_ID.$MONITOR_DOMAIN;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Rate limiting (applied per location)
    limit_req zone=api burst=20 nodelay;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint (no auth required)
    location /health {
        proxy_pass http://localhost:3000/health;
        access_log off;
    }
}
EOF
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/gridpane-manager-api /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}✓ Nginx reverse proxy configured${NC}"
    else
        echo -e "${YELLOW}⚠ Nginx configuration test failed - please check manually${NC}"
    fi
fi

# Open firewall for backend port
ufw allow 3000/tcp > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configured (port 3000)${NC}"

# Display completion message
echo
echo -e "${BLUE}Installation Complete!${NC}"
echo "===================="

if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ GridPane Manager Backend is running${NC}"
    echo -e "${GREEN}✓ Service: $SERVICE_NAME${NC}"
    echo -e "${GREEN}✓ Port: 3000${NC}"
    
    if [ -n "$SERVER_ID" ]; then
        echo -e "${BLUE}✓ Server ID: $SERVER_ID${NC}"
    fi
    
    if [ -n "$MONITOR_DOMAIN" ]; then
        echo -e "${BLUE}✓ Monitor Domain: $MONITOR_DOMAIN${NC}"
        echo -e "${BLUE}✓ SSL Endpoint: https://$SERVER_ID.$MONITOR_DOMAIN${NC}"
    else
        echo -e "${BLUE}✓ HTTP Endpoint: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP'):3000${NC}"
    fi
    
    echo -e "${GREEN}✓ Logs: journalctl -u $SERVICE_NAME -f${NC}"
    
    # Display API key
    API_KEY=$(grep API_KEY $CONFIG_DIR/.env | cut -d'=' -f2)
    echo -e "${BLUE}✓ API Key: $API_KEY${NC}"
    
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    if [ -n "$MONITOR_DOMAIN" ] && [ -n "$SERVER_ID" ]; then
        echo "1. Add DNS A record in CloudFlare for $MONITOR_DOMAIN:"
        echo "   - Type: A"
        echo "   - Name: $SERVER_ID"
        echo "   - IPv4: $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
        echo "   - Proxy: ON (orange cloud)"
        echo "2. Test HTTPS endpoint: https://$SERVER_ID.$MONITOR_DOMAIN/api/health"
        echo "3. Configure iOS app with API key: $API_KEY"
    else
        echo "1. MANUAL CONFIGURATION (Recommended):"
        echo "   sudo nano /etc/gridpane-manager/.env"
        echo "   Set: SERVER_ID=your-server-name"
        echo "   Set: MONITOR_DOMAIN=yourdomain.com"
        echo "   Set: BACKEND_URL=https://your-server-name.yourdomain.com"
        echo "   Then: sudo systemctl restart gridpane-manager"
        echo "2. Test HTTP endpoint: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP'):3000/api/health"
        echo "3. Configure iOS app with API key: $API_KEY"
    fi
    
    echo
    echo -e "${BLUE}Manual Configuration (Production Recommended):${NC}"
    echo "If you need to customize settings after installation:"
    echo "1. Edit: sudo nano /etc/gridpane-manager/.env"
    echo "2. Restart: sudo systemctl restart gridpane-manager"
    echo "3. Verify: curl http://localhost:3000/api/health"
    
    echo
    echo -e "${YELLOW}Service Management:${NC}"
    echo "- Start:   systemctl start $SERVICE_NAME"
    echo "- Stop:    systemctl stop $SERVICE_NAME"
    echo "- Restart: systemctl restart $SERVICE_NAME"
    echo "- Status:  systemctl status $SERVICE_NAME"
    echo "- Logs:    journalctl -u $SERVICE_NAME -f"
    
    echo
    echo -e "${GREEN}GridPane Manager Backend is ready!${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo -e "${YELLOW}Check logs: journalctl -u $SERVICE_NAME${NC}"
    exit 1
fi
