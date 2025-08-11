#!/bin/bash

# Holler Server Agent Installation Script
# One-line installer for the Holler Server Agent
# Usage: curl -sSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash

set -euo pipefail

# Configuration
REPO_URL="https://github.com/HollerDigital/holler-server-monitoring-agent"
INSTALL_DIR="/opt/holler-agent"
SERVICE_NAME="holler-agent"
SERVICE_USER="holler-agent"
LOG_DIR="/var/log/holler-agent"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo ""
echo "🚀 Holler Server Agent Installation"
echo "===================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_step "Checking system requirements..."

# Check Node.js installation
if command -v node &> /dev/null; then
    CURRENT_NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    log_info "Found Node.js $(node --version)"
    
    if [ "$CURRENT_NODE_VERSION" -lt 16 ]; then
        log_error "Node.js 16+ is required. Current version: $(node --version)"
        exit 1
    fi
else
    log_error "Node.js is not installed. Please install Node.js 16+ first."
    exit 1
fi

# Check for required system packages
log_info "Checking system dependencies..."
MISSING_PACKAGES=()

if ! command -v git &> /dev/null; then
    MISSING_PACKAGES+=("git")
fi

if ! command -v curl &> /dev/null; then
    MISSING_PACKAGES+=("curl")
fi

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    log_error "Missing required packages: ${MISSING_PACKAGES[*]}"
    log_info "Install them with: apt update && apt install -y ${MISSING_PACKAGES[*]}"
    exit 1
fi

log_info "✓ System requirements met"

log_step "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

log_step "Downloading latest release..."
cd "$INSTALL_DIR"
if [ -d ".git" ]; then
    log_info "Updating existing installation..."
    git pull
else
    log_info "Cloning repository..."
    git clone "$REPO_URL" .
fi

log_step "Installing dependencies..."
npm install --production --no-audit --no-fund

log_step "Setting up system user and permissions..."

# Create system user
if ! id "$SERVICE_USER" &>/dev/null; then
    log_info "Creating system user: $SERVICE_USER"
    useradd --system --shell /bin/false --home-dir "$INSTALL_DIR" --no-create-home "$SERVICE_USER"
else
    log_info "System user $SERVICE_USER already exists"
fi

# Set ownership and permissions
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
chmod 755 "$INSTALL_DIR"
chmod 755 "$LOG_DIR"

# Create sudoers configuration for service control
log_info "Configuring sudoers for service control..."
cat > "/etc/sudoers.d/$SERVICE_USER" << EOF
# Allow $SERVICE_USER to manage system services
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart nginx
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart mysql
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart mariadb
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart php*-fpm
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart redis
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl restart redis-server
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start nginx
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start mysql
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start mariadb
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start php*-fpm
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start redis
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl start redis-server
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop nginx
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop mysql
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop mariadb
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop php*-fpm
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop redis
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl stop redis-server
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl reload nginx
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl reload mysql
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl reload mariadb
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl reload php*-fpm
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status nginx
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status mysql
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status mariadb
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status php*-fpm
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status redis
$SERVICE_USER ALL=(root) NOPASSWD: /bin/systemctl status redis-server
EOF

# Validate sudoers file
if visudo -c -f "/etc/sudoers.d/$SERVICE_USER"; then
    log_info "Sudoers configuration validated successfully"
else
    log_error "Sudoers configuration is invalid"
    rm -f "/etc/sudoers.d/$SERVICE_USER"
    exit 1
fi

# Create D-Bus policy for systemd operations
log_info "Configuring D-Bus policy..."
cat > "/etc/dbus-1/system.d/$SERVICE_NAME.conf" << EOF
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" 
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="$SERVICE_USER">
    <allow send_destination="org.freedesktop.systemd1"/>
    <allow send_interface="org.freedesktop.systemd1.Manager"/>
    <allow send_interface="org.freedesktop.systemd1.Unit"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
    <allow send_interface="org.freedesktop.DBus.Introspectable"/>
    <allow send_member="RestartUnit"/>
    <allow send_member="StartUnit"/>
    <allow send_member="StopUnit"/>
    <allow send_member="ReloadUnit"/>
    <allow send_member="GetUnit"/>
    <allow send_member="ListUnits"/>
    <!-- Allow authentication for systemd operations -->
    <allow send_destination="org.freedesktop.PolicyKit1"/>
    <allow send_interface="org.freedesktop.PolicyKit1.Authority"/>
  </policy>
</busconfig>
EOF

# Create PolicyKit rules for systemd operations
log_info "Configuring PolicyKit rules..."
cat > "/etc/polkit-1/rules.d/50-$SERVICE_NAME.rules" << EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.systemd1.manage-units" ||
         action.id == "org.freedesktop.systemd1.manage-unit-files" ||
         action.id == "org.freedesktop.systemd1.reload-daemon") &&
        subject.user == "$SERVICE_USER") {
        return polkit.Result.YES;
    }
});

polkit.addRule(function(action, subject) {
    if (action.id.match("org.freedesktop.systemd1") &&
        subject.user == "$SERVICE_USER") {
        return polkit.Result.YES;
    }
});
EOF

log_step "Configuring environment..."

# Generate secure API key
API_KEY=$(openssl rand -hex 32)

# Create environment file
cat > "$INSTALL_DIR/.env" << EOF
# Holler Server Agent Configuration
NODE_ENV=production
PORT=3001
HOST=127.0.0.1

# API Security
API_KEY=$API_KEY

# Logging
LOG_DIR=$LOG_DIR
LOG_LEVEL=info
LOG_MAX_SIZE=20m
LOG_MAX_FILES=14d

# Agent Configuration
AGENT_ID=agent-\$(hostname)
AGENT_NAME=Holler Agent - \$(hostname)
AGENT_VERSION=2.1.0
AGENT_MODE=agent

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX=100

# Security
ALLOWED_IPS=127.0.0.1,::1
EOF

chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env"
chmod 600 "$INSTALL_DIR/.env"

log_info "Generated secure API key: $API_KEY"
log_warn "Save this API key - you'll need it to connect to the agent!"

log_step "Configuring systemd service..."

# Create systemd service file
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Holler Server Agent - Secure Server Management
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node src/agent-server.js
Restart=always
RestartSec=10
EnvironmentFile=$INSTALL_DIR/.env

# Security settings
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $INSTALL_DIR
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

log_step "Starting Holler Agent..."

# Restart services to apply D-Bus and PolicyKit changes
systemctl restart dbus
systemctl restart polkit

# Start the agent service
if systemctl start "$SERVICE_NAME"; then
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "✅ Holler Agent started successfully!"
        
        # Test the health endpoint
        if curl -s -H "X-API-Key: $API_KEY" http://127.0.0.1:3001/health > /dev/null; then
            log_info "✅ API health check passed"
        else
            log_warn "⚠️  API health check failed - agent may still be starting"
        fi
    else
        log_error "❌ Agent failed to start"
        log_info "Check logs: journalctl -u $SERVICE_NAME -n 20"
        exit 1
    fi
else
    log_error "❌ Failed to start agent service"
    log_info "Check logs: journalctl -u $SERVICE_NAME -n 20"
    exit 1
fi

echo ""
echo "🎉 Installation Complete!"
echo "========================"
echo ""
log_info "Holler Server Agent is now running on http://127.0.0.1:3001"
log_info "API Key: $API_KEY"
log_info "Service: $SERVICE_NAME"
log_info "User: $SERVICE_USER"
log_info "Directory: $INSTALL_DIR"
log_info "Logs: $LOG_DIR"
echo ""
log_info "Test the agent:"
echo "  curl -H \"X-API-Key: $API_KEY\" http://127.0.0.1:3001/health"
echo ""
log_info "Manage the service:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo ""
log_info "Update the agent:"
echo "  curl -sSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/update-agent.sh | sudo bash"
echo ""
log_info "Uninstall the agent:"
echo "  curl -sSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/uninstall-agent.sh | sudo bash"
echo ""
