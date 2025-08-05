#!/bin/bash

# GridPane Manager Backend - Minimal Installation Script
# Fixes syntax errors and provides clean installation

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
LOG_DIR="/var/log/gridpane-manager"
CONFIG_DIR="/etc/gridpane-manager"

echo -e "${BLUE}GridPane Manager Backend Installation (Minimal)${NC}"
echo "================================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check Node.js
echo -e "${YELLOW}Checking Node.js installation...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js not found. Please install Node.js 18+ first${NC}"
    exit 1
fi

NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 16 ]; then
    echo -e "${RED}Node.js version 16 or higher is required${NC}"
    exit 1
fi

echo -e "${GREEN}Node.js $(node --version) found${NC}"

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# Create service user
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating service user: $SERVICE_USER${NC}"
    useradd --system --shell /bin/false --home "$INSTALL_DIR" "$SERVICE_USER" || true
fi

# Get user's primary group
USER_GROUP=$(id -gn "$SERVICE_USER")
echo -e "${GREEN}User $SERVICE_USER primary group: $USER_GROUP${NC}"

# Set permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R "$SERVICE_USER:$USER_GROUP" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$USER_GROUP" "$LOG_DIR"

# Install application files
echo -e "${YELLOW}Installing application files...${NC}"
if [ ! -f "package.json" ]; then
    echo "Cloning repository..."
    git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git .
fi

# Install dependencies
echo -e "${YELLOW}Installing Node.js dependencies...${NC}"
sudo -u "$SERVICE_USER" npm install --production

# Interactive configuration
echo -e "${YELLOW}Server Configuration:${NC}"

# Get Server ID
DEFAULT_SERVER_ID=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
read -p "Enter Server ID [$DEFAULT_SERVER_ID]: " SERVER_ID
SERVER_ID=${SERVER_ID:-$DEFAULT_SERVER_ID}

# Get Monitor Domain
read -p "Enter Monitor Domain (e.g., hollerdigital.dev) or press Enter to skip: " MONITOR_DOMAIN

# Get API Key
read -p "Enter API Key or press Enter to generate: " USER_API_KEY

# Create environment file
echo -e "${YELLOW}Creating environment configuration...${NC}"
if [ ! -f "$CONFIG_DIR/.env" ]; then
    cp .env.example "$CONFIG_DIR/.env"
    
    # Generate JWT secret and setup token
    JWT_SECRET=$(openssl rand -base64 32)
    SETUP_TOKEN=$(openssl rand -hex 16)
    
    # Update environment file
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" "$CONFIG_DIR/.env"
    
    if [ -n "$USER_API_KEY" ]; then
        sed -i "s|API_KEY=.*|API_KEY=$USER_API_KEY|" "$CONFIG_DIR/.env"
    else
        API_KEY=$(openssl rand -hex 32)
        sed -i "s|API_KEY=.*|API_KEY=$API_KEY|" "$CONFIG_DIR/.env"
        echo "SETUP_TOKEN=$SETUP_TOKEN" >> "$CONFIG_DIR/.env"
    fi
    
    # Add server configuration
    echo "SERVER_ID=$SERVER_ID" >> "$CONFIG_DIR/.env"
    
    if [ -n "$MONITOR_DOMAIN" ]; then
        echo "MONITOR_DOMAIN=$MONITOR_DOMAIN" >> "$CONFIG_DIR/.env"
        echo "BACKEND_URL=https://$SERVER_ID.$MONITOR_DOMAIN" >> "$CONFIG_DIR/.env"
        echo -e "${GREEN}✓ Monitor Domain: $MONITOR_DOMAIN${NC}"
        echo -e "${GREEN}✓ SSL Endpoint: https://$SERVER_ID.$MONITOR_DOMAIN${NC}"
    fi
    
    echo -e "${GREEN}Environment file created${NC}"
fi

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/$SERVICE_NAME.service << 'EOF'
[Unit]
Description=GridPane Manager Backend API
After=network.target

[Service]
Type=simple
User=gridpane-manager
Group=users
WorkingDirectory=/opt/gridpane-manager
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
EnvironmentFile=/etc/gridpane-manager/.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gridpane-manager

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo -e "${YELLOW}Starting service...${NC}"
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Check status
sleep 2
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ GridPane Manager Backend is running${NC}"
    echo -e "${GREEN}✓ Service: $SERVICE_NAME${NC}"
    echo -e "${GREEN}✓ Server ID: $SERVER_ID${NC}"
    
    if [ -n "$MONITOR_DOMAIN" ]; then
        echo -e "${GREEN}✓ SSL Endpoint: https://$SERVER_ID.$MONITOR_DOMAIN${NC}"
    else
        echo -e "${GREEN}✓ HTTP Endpoint: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP'):3000${NC}"
    fi
    
    API_KEY=$(grep API_KEY $CONFIG_DIR/.env | cut -d'=' -f2)
    echo -e "${BLUE}✓ API Key: $API_KEY${NC}"
    
    echo -e "${GREEN}Installation Complete!${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo -e "${YELLOW}Check logs: journalctl -u $SERVICE_NAME${NC}"
    exit 1
fi
