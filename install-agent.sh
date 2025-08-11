#!/bin/bash

# Server Agent One-Line Installer
# Usage: curl -sSL https://raw.githubusercontent.com/your-repo/holler-server-monitoring-agent/main/install-agent.sh | sudo bash

set -e

# Configuration
REPO_URL="https://github.com/your-repo/holler-server-monitoring-agent"
INSTALL_DIR="/opt/server-agent"
SERVICE_NAME="server-agent"
AGENT_USER="svc-control"

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Starting Server Agent installation..."
log_info "This will install a minimal HTTPS API for server control operations"

# Check system requirements
log_step "Checking system requirements..."

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    log_error "systemd is required but not found"
    exit 1
fi

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    log_error "Node.js is required but not found"
    log_info "Please install Node.js 16+ first:"
    log_info "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
    log_info "  sudo apt-get install -y nodejs"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [[ $NODE_VERSION -lt 16 ]]; then
    log_error "Node.js 16+ is required (found v$NODE_VERSION)"
    exit 1
fi

log_info "✓ System requirements met"

# Stop existing service if running
if systemctl is-active --quiet $SERVICE_NAME; then
    log_step "Stopping existing service..."
    systemctl stop $SERVICE_NAME
fi

# Create installation directory
log_step "Creating installation directory..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download and extract latest release
log_step "Downloading latest release..."
if command -v git &> /dev/null; then
    # Use git if available
    if [[ -d ".git" ]]; then
        git pull
    else
        git clone $REPO_URL.git .
    fi
else
    # Fallback to curl/wget
    if command -v curl &> /dev/null; then
        curl -sSL $REPO_URL/archive/main.tar.gz | tar -xz --strip-components=1
    elif command -v wget &> /dev/null; then
        wget -qO- $REPO_URL/archive/main.tar.gz | tar -xz --strip-components=1
    else
        log_error "git, curl, or wget is required to download the agent"
        exit 1
    fi
fi

# Install Node.js dependencies
log_step "Installing dependencies..."
npm install --production --silent

# Set up system user and permissions
log_step "Setting up system user and permissions..."
chmod +x scripts/setup-system-user.sh
./scripts/setup-system-user.sh

# Configure environment
log_step "Configuring environment..."
if [[ ! -f ".env" ]]; then
    cp .env.agent .env
    
    # Generate secure API key
    API_KEY=$(openssl rand -hex 32)
    sed -i "s/your-secure-api-key-here/$API_KEY/" .env
    
    log_info "Generated secure API key: $API_KEY"
    log_warn "Save this API key - you'll need it to connect to the agent!"
fi

# Set ownership
chown -R $AGENT_USER:$AGENT_USER $INSTALL_DIR

# Update systemd service file to use agent server
log_step "Configuring systemd service..."
sed -i "s|ExecStart=/usr/bin/node.*|ExecStart=/usr/bin/node $INSTALL_DIR/src/agent-server.js|" /etc/systemd/system/$SERVICE_NAME.service

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable $SERVICE_NAME

# Start the service
log_step "Starting server agent..."
systemctl start $SERVICE_NAME

# Wait a moment for service to start
sleep 3

# Check service status
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "✓ Server Agent installed and started successfully!"
    
    # Get service info
    AGENT_PORT=$(grep AGENT_PORT .env | cut -d'=' -f2 | tr -d ' ')
    AGENT_HOST=$(grep AGENT_HOST .env | cut -d'=' -f2 | tr -d ' ')
    API_KEY=$(grep AGENT_API_KEY .env | cut -d'=' -f2 | tr -d ' ')
    
    echo ""
    log_info "=== Installation Complete ==="
    log_info "Service: $SERVICE_NAME"
    log_info "Status: $(systemctl is-active $SERVICE_NAME)"
    log_info "Endpoint: http://$AGENT_HOST:$AGENT_PORT"
    log_info "API Key: $API_KEY"
    echo ""
    log_info "Test the installation:"
    log_info "  curl -H 'X-API-Key: $API_KEY' http://$AGENT_HOST:$AGENT_PORT/health"
    echo ""
    log_info "View logs:"
    log_info "  sudo journalctl -u $SERVICE_NAME -f"
    echo ""
    log_info "Control the service:"
    log_info "  sudo systemctl {start|stop|restart|status} $SERVICE_NAME"
    
else
    log_error "Service failed to start"
    log_info "Check logs: sudo journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi

# Optional: Test basic functionality
log_step "Testing basic functionality..."
sleep 2

AGENT_PORT=$(grep AGENT_PORT .env | cut -d'=' -f2 | tr -d ' ')
AGENT_HOST=$(grep AGENT_HOST .env | cut -d'=' -f2 | tr -d ' ')
API_KEY=$(grep AGENT_API_KEY .env | cut -d'=' -f2 | tr -d ' ')

if curl -s -H "X-API-Key: $API_KEY" "http://$AGENT_HOST:$AGENT_PORT/health" > /dev/null; then
    log_info "✓ Agent is responding to API calls"
else
    log_warn "Agent may not be responding properly - check logs"
fi

log_info ""
log_info "🎉 Server Agent installation completed successfully!"
log_info ""
log_warn "IMPORTANT SECURITY NOTES:"
log_info "1. The agent runs on localhost only by default"
log_info "2. Change the API key in .env if needed"
log_info "3. Configure firewall rules if exposing to network"
log_info "4. Consider enabling HTTPS for production use"
