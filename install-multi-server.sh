#!/bin/bash

# GridPane Manager Backend - Multi-Server Install Script
# Supports flexible deployment across multiple servers with custom subdomains

set -e

# Colors for output
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
REPO_URL="https://github.com/yourusername/holler-server-monitoring-agent.git"

# Default values
DEFAULT_PORT=3000
DEFAULT_SUBDOMAIN="gridpane-api"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  GridPane Manager Backend Installer  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local result
    
    read -p "$prompt [$default]: " result
    echo "${result:-$default}"
}

# Function to validate domain format
validate_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if domain resolves to current server
check_domain_resolution() {
    local domain="$1"
    local server_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    local resolved_ip=$(dig +short "$domain" | tail -n1)
    
    if [[ "$resolved_ip" == "$server_ip" ]]; then
        return 0
    else
        echo -e "${YELLOW}Warning: $domain resolves to $resolved_ip, but server IP is $server_ip${NC}"
        return 1
    fi
}

# Collect configuration
echo -e "${YELLOW}Configuration Setup${NC}"
echo "Please provide the following information:"
echo ""

# Get domain information
while true; do
    DOMAIN=$(prompt_with_default "Enter your domain (e.g., yourdomain.com)" "")
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}Domain is required${NC}"
        continue
    fi
    if validate_domain "$DOMAIN"; then
        break
    else
        echo -e "${RED}Invalid domain format${NC}"
    fi
done

SUBDOMAIN=$(prompt_with_default "Enter subdomain for API" "$DEFAULT_SUBDOMAIN")
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"

echo ""
echo -e "${BLUE}API will be accessible at: https://$FULL_DOMAIN${NC}"
echo ""

# Check DNS resolution
echo -e "${YELLOW}Checking DNS resolution...${NC}"
if check_domain_resolution "$FULL_DOMAIN"; then
    echo -e "${GREEN}✓ DNS resolution looks good${NC}"
else
    echo -e "${YELLOW}Please ensure $FULL_DOMAIN points to this server's IP address${NC}"
    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        echo "Exiting. Please configure DNS and try again."
        exit 1
    fi
fi

# Get port configuration
PORT=$(prompt_with_default "Backend port" "$DEFAULT_PORT")

# SSL Configuration
echo ""
echo -e "${YELLOW}SSL Configuration${NC}"
echo "Choose SSL setup method:"
echo "1) CloudFlare (Flexible SSL) - Recommended"
echo "2) Let's Encrypt (Full SSL)"
echo "3) Manual/External SSL"
echo ""
SSL_METHOD=$(prompt_with_default "SSL method (1-3)" "1")

# Get API key
echo ""
API_KEY=$(prompt_with_default "API Key (leave blank to generate)" "")
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(openssl rand -hex 32)
    echo -e "${GREEN}Generated API Key: $API_KEY${NC}"
fi

echo ""
echo -e "${YELLOW}Starting installation...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Install Node.js if not present
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}Installing Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi

# Create service user
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating service user...${NC}"
    useradd --system --home-dir "$INSTALL_DIR" --shell /bin/false "$SERVICE_USER"
fi

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Clone or update repository
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${YELLOW}Updating existing installation...${NC}"
    cd "$INSTALL_DIR"
    git pull
else
    echo -e "${YELLOW}Cloning repository...${NC}"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
npm install --production

# Create configuration file
echo -e "${YELLOW}Creating configuration...${NC}"
cat > "$CONFIG_DIR/.env" << EOF
# GridPane Manager Backend Configuration
NODE_ENV=production
PORT=$PORT
API_KEY=$API_KEY
DOMAIN=$FULL_DOMAIN

# Logging
LOG_LEVEL=info
LOG_DIR=$LOG_DIR

# Security
JWT_SECRET=$(openssl rand -hex 64)
CORS_ORIGIN=https://$FULL_DOMAIN

# GridPane Integration
GRIDPANE_API_URL=https://api.gridpane.com
EOF

# Set permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
chmod 600 "$CONFIG_DIR/.env"

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=GridPane Manager Backend API
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=NODE_ENV=production
EnvironmentFile=$CONFIG_DIR/.env
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
echo -e "${YELLOW}Configuring Nginx...${NC}"
cat > "/etc/nginx/sites-available/$FULL_DOMAIN" << EOF
server {
    listen 80;
    server_name $FULL_DOMAIN;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support (for future features)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Enable Nginx site
ln -sf "/etc/nginx/sites-available/$FULL_DOMAIN" "/etc/nginx/sites-enabled/"
nginx -t && systemctl reload nginx

# Handle SSL setup based on method
case $SSL_METHOD in
    1)
        echo -e "${GREEN}✓ Nginx configured for CloudFlare Flexible SSL${NC}"
        echo -e "${YELLOW}Make sure to set CloudFlare SSL mode to 'Flexible'${NC}"
        ;;
    2)
        echo -e "${YELLOW}Setting up Let's Encrypt...${NC}"
        if command -v certbot &> /dev/null; then
            certbot --nginx -d "$FULL_DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN"
        else
            echo -e "${YELLOW}Installing Certbot...${NC}"
            apt-get update && apt-get install -y certbot python3-certbot-nginx
            certbot --nginx -d "$FULL_DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN"
        fi
        ;;
    3)
        echo -e "${YELLOW}Manual SSL configuration required${NC}"
        echo -e "${YELLOW}Please configure SSL certificates manually for $FULL_DOMAIN${NC}"
        ;;
esac

# Start and enable service
echo -e "${YELLOW}Starting service...${NC}"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Verify service status
sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}✓ Service started successfully${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo "Check logs: journalctl -u $SERVICE_NAME"
    exit 1
fi

# Final output
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}API Endpoint:${NC} https://$FULL_DOMAIN"
echo -e "${BLUE}API Key:${NC} $API_KEY"
echo -e "${BLUE}Service:${NC} $SERVICE_NAME"
echo -e "${BLUE}Logs:${NC} journalctl -u $SERVICE_NAME -f"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Test API: curl https://$FULL_DOMAIN/health"
echo "2. Add API endpoint to iOS app"
echo "3. Configure monitoring and alerts"
echo ""
echo -e "${GREEN}Installation successful!${NC}"
