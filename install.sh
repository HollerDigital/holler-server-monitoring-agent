#!/bin/bash

# GridPane Manager Backend Installation Script
# Installs and configures the Node.js backend service
# Upgraded from Python Flask to Node.js Express for iOS app integration

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

echo -e "${BLUE}GridPane Manager Backend Installation${NC}"
echo "======================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Install or update Node.js
echo -e "${YELLOW}Checking Node.js installation...${NC}"

# Check if Node.js is installed and get version
if command -v node &> /dev/null; then
    CURRENT_NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    echo -e "${GREEN}Found Node.js v$(node --version)${NC}"
    
    if [ "$CURRENT_NODE_VERSION" -lt 16 ]; then
        echo -e "${YELLOW}Node.js version $CURRENT_NODE_VERSION is too old. Upgrading to Node.js 18.x...${NC}"
        echo -e "${YELLOW}Removing conflicting Node.js packages (common on GridPane servers)...${NC}"
        
        # Remove conflicting packages that prevent Node.js 18.x installation
        apt-get remove -y libnode-dev nodejs-doc npm || true
        apt-get autoremove -y || true
        
        # Clear any package locks
        dpkg --configure -a || true
        
        # Install Node.js 18.x
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        apt-get update
        apt-get install -y nodejs
        
        # Verify installation worked
        if ! command -v node &> /dev/null; then
            echo -e "${RED}Node.js installation failed. Please run manual cleanup:${NC}"
            echo -e "${YELLOW}sudo apt-get remove --purge nodejs npm libnode-dev nodejs-doc${NC}"
            echo -e "${YELLOW}sudo apt-get autoremove -y${NC}"
            echo -e "${YELLOW}sudo apt-get autoclean${NC}"
            echo -e "${YELLOW}curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -${NC}"
            echo -e "${YELLOW}sudo apt-get install -y nodejs${NC}"
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}Node.js not found. Installing Node.js 18.x...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    apt-get install -y nodejs
fi

# Verify final Node.js installation
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

# Create directories first
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# Create service user
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating service user: $SERVICE_USER${NC}"
    # Create user without home directory first, then set home
    if useradd --system --shell /bin/false --no-create-home "$SERVICE_USER"; then
        echo -e "${GREEN}Service user created successfully${NC}"
        # Set the home directory manually
        usermod --home "$INSTALL_DIR" "$SERVICE_USER"
    else
        echo -e "${RED}Failed to create service user. Checking if user exists...${NC}"
        if id "$SERVICE_USER" &>/dev/null; then
            echo -e "${YELLOW}User $SERVICE_USER already exists, continuing...${NC}"
        else
            echo -e "${RED}Failed to create or find service user${NC}"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}Service user $SERVICE_USER already exists${NC}"
fi

# Verify user exists before setting permissions
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${RED}Service user $SERVICE_USER does not exist. Cannot set permissions.${NC}"
    exit 1
fi

# Get the user's primary group
USER_GROUP=$(id -gn "$SERVICE_USER" 2>/dev/null)
if [ -z "$USER_GROUP" ]; then
    echo -e "${RED}Cannot determine primary group for user $SERVICE_USER${NC}"
    exit 1
fi

echo -e "${GREEN}User $SERVICE_USER primary group: $USER_GROUP${NC}"

# Set permissions using the actual primary group
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R "$SERVICE_USER:$USER_GROUP" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$USER_GROUP" "$LOG_DIR"

# Copy application files
echo -e "${YELLOW}Installing application files...${NC}"
if [ -f "package.json" ]; then
    # Running from cloned repository directory
    cp -r . "$INSTALL_DIR/"
    cd "$INSTALL_DIR"
else
    # Running from one-liner curl command - need to clone repository
    echo -e "${YELLOW}package.json not found. Cloning repository...${NC}"
    cd /tmp
    rm -rf holler-server-monitoring-agent
    git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
    cd holler-server-monitoring-agent
    
    if [ ! -f "package.json" ]; then
        echo -e "${RED}Failed to clone repository or package.json still not found${NC}"
        exit 1
    fi
    
    # Copy files to install directory
    cp -r . "$INSTALL_DIR/"
    cd "$INSTALL_DIR"
fi

# Install dependencies
echo -e "${YELLOW}Installing Node.js dependencies...${NC}"
sudo -u "$SERVICE_USER" npm install --production

# Create environment file
if [ ! -f "$CONFIG_DIR/.env" ]; then
    echo -e "${YELLOW}Creating environment configuration...${NC}"
    cp .env.example "$CONFIG_DIR/.env"
    
    # Generate random JWT secret
    JWT_SECRET=$(openssl rand -base64 32)
    API_KEY=$(openssl rand -hex 32)
    
    # Use | as delimiter to avoid conflicts with / in base64 strings
    sed -i "s|your-super-secure-jwt-secret-key-here|$JWT_SECRET|" "$CONFIG_DIR/.env"
    sed -i "s|your-api-key-here|$API_KEY|" "$CONFIG_DIR/.env"
    
    echo -e "${GREEN}Environment file created at $CONFIG_DIR/.env${NC}"
    echo -e "${YELLOW}Please edit $CONFIG_DIR/.env to configure your settings${NC}"
fi

# Create systemd service file
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=GridPane Manager Backend API
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$USER_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node src/server.js
EnvironmentFile=$CONFIG_DIR/.env
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
ReadWritePaths=$LOG_DIR $CONFIG_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

# Create logrotate configuration
echo -e "${YELLOW}Setting up log rotation...${NC}"
cat > /etc/logrotate.d/$SERVICE_NAME << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_USER
    postrotate
        systemctl reload $SERVICE_NAME > /dev/null 2>&1 || true
    endscript
}
EOF

# Set up sudoers for service control
echo -e "${YELLOW}Configuring sudo permissions...${NC}"
cat > /etc/sudoers.d/$SERVICE_NAME << EOF
# Allow gridpane-manager service to restart system services
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart mysql
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart mysqld
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart mariadb
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart apache2
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart php*-fpm
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl is-active *
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl is-enabled *
$SERVICE_USER ALL=(ALL) NOPASSWD: /sbin/shutdown -r +1 *
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/local/bin/gp *
EOF

# Stop old Python service if it exists
if systemctl is-active --quiet gridpane-monitor 2>/dev/null; then
    echo -e "${YELLOW}Stopping old Python monitoring service...${NC}"
    systemctl stop gridpane-monitor
    systemctl disable gridpane-monitor
fi

# Reload systemd and enable service
echo -e "${YELLOW}Enabling and starting service...${NC}"
systemctl daemon-reload
systemctl enable $SERVICE_NAME

# Start the service
if systemctl start $SERVICE_NAME; then
    echo -e "${GREEN}Service started successfully${NC}"
else
    echo -e "${RED}Failed to start service. Check logs with: journalctl -u $SERVICE_NAME${NC}"
    exit 1
fi

# Check service status
sleep 2
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ GridPane Manager Backend is running${NC}"
    echo -e "${GREEN}✓ Service: $SERVICE_NAME${NC}"
    echo -e "${GREEN}✓ Port: $(grep PORT $CONFIG_DIR/.env | cut -d'=' -f2 || echo '3000')${NC}"
    echo -e "${GREEN}✓ Logs: journalctl -u $SERVICE_NAME -f${NC}"
    
    # Display API key for initial setup
    API_KEY=$(grep API_KEY $CONFIG_DIR/.env | cut -d'=' -f2)
    echo -e "${BLUE}✓ API Key: $API_KEY${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo -e "${YELLOW}Check logs: journalctl -u $SERVICE_NAME${NC}"
    exit 1
fi

# Display next steps
echo ""
echo -e "${BLUE}Installation Complete!${NC}"
echo "===================="
echo -e "${YELLOW}Migration Notes:${NC}"
echo "- Upgraded from Python Flask to Node.js Express"
echo "- Service name changed from 'gridpane-monitor' to 'gridpane-manager'"
echo "- Default port changed from 8847 to 3000"
echo "- Enhanced security and iOS app integration"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Edit configuration: $CONFIG_DIR/.env"
echo "2. Configure SSL/TLS certificates"
echo "3. Set up firewall rules for the API port"
echo "4. Test the API: curl http://localhost:3000/health"
echo ""
echo -e "${YELLOW}Service Management:${NC}"
echo "- Start:   systemctl start $SERVICE_NAME"
echo "- Stop:    systemctl stop $SERVICE_NAME"
echo "- Restart: systemctl restart $SERVICE_NAME"
echo "- Status:  systemctl status $SERVICE_NAME"
echo "- Logs:    journalctl -u $SERVICE_NAME -f"
echo ""
echo -e "${GREEN}GridPane Manager Backend is ready!${NC}"
