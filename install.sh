#!/bin/bash
set -euo pipefail

# GridPane Manager Backend Installation Script
# Installs and configures the Node.js backend service
# Upgraded from Python Flask to Node.js Express for iOS app integration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

check_dependencies() {
    log "Checking dependencies..."
    
    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed"
    fi
    
    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        log "Installing pip3..."
        apt-get update
        apt-get install -y python3-pip
    fi
    
    # Install required Python packages
    log "Installing Python dependencies..."
    pip3 install flask flask-limiter flask-httpauth pyjwt psutil
}

create_user() {
    log "Creating dedicated user and group..."
    
    # Create group if it doesn't exist
    if ! getent group "$GROUP_NAME" > /dev/null 2>&1; then
        groupadd --system "$GROUP_NAME"
        log "Created group: $GROUP_NAME"
    fi
    
    # Create user if it doesn't exist
    if ! getent passwd "$USER_NAME" > /dev/null 2>&1; then
        useradd --system --gid "$GROUP_NAME" --home-dir "$INSTALL_DIR" \
                --shell /bin/false --comment "GridPane Monitor" "$USER_NAME"
        log "Created user: $USER_NAME"
    fi
}

setup_directories() {
    log "Setting up directories..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Set ownership and permissions
    chown "$USER_NAME:$GROUP_NAME" "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"
    
    log "Created directory: $INSTALL_DIR"
}

install_agent() {
    log "Installing monitoring agent..."
    
    # Copy the Python script
    if [[ -f "gridpane_monitor.py" ]]; then
        cp gridpane_monitor.py "$INSTALL_DIR/"
        chown "$USER_NAME:$GROUP_NAME" "$INSTALL_DIR/gridpane_monitor.py"
        chmod 750 "$INSTALL_DIR/gridpane_monitor.py"
    else
        error "gridpane_monitor.py not found in current directory"
    fi
    
    log "Installed monitoring agent"
}

install_service() {
    log "Installing systemd service..."
    
    # Copy service file
    if [[ -f "gridpane-monitor.service" ]]; then
        cp gridpane-monitor.service "$SERVICE_FILE"
        chmod 644 "$SERVICE_FILE"
    else
        error "gridpane-monitor.service not found in current directory"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    log "Installed systemd service"
}

configure_firewall() {
    log "Configuring firewall..."
    
    # The service only binds to localhost, so no firewall rules needed
    # But we can add extra security if UFW is installed
    if command -v ufw &> /dev/null; then
        warn "UFW detected. The monitoring agent only binds to localhost (127.0.0.1:8847)"
        warn "Access requires SSH tunnel: ssh -L 8847:localhost:8847 user@server"
    fi
}

generate_api_key() {
    log "Starting service to generate API key..."
    
    # Start the service temporarily to generate keys
    systemctl start gridpane-monitor
    sleep 3
    
    # Get the API key from logs
    API_KEY=$(journalctl -u gridpane-monitor --no-pager -n 20 | grep "API Key:" | tail -1 | awk '{print $NF}')
    
    if [[ -n "$API_KEY" ]]; then
        log "API Key generated: $API_KEY"
        echo ""
        echo -e "${GREEN}=== IMPORTANT: SAVE THIS API KEY ===${NC}"
        echo -e "${YELLOW}API Key: $API_KEY${NC}"
        echo -e "${GREEN}====================================${NC}"
        echo ""
        echo "You will need this API key to authenticate from your iOS app."
        echo "The key is also stored securely in: $INSTALL_DIR/.api_key"
        echo ""
    else
        warn "Could not extract API key from logs. Check service status."
    fi
    
    # Stop the service for now
    systemctl stop gridpane-monitor
}

setup_log_rotation() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/gridpane-monitor << EOF
$INSTALL_DIR/monitor.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    su $USER_NAME $GROUP_NAME
}
EOF
    
    log "Log rotation configured"
}

main() {
    log "Starting GridPane Monitoring Agent installation..."
    
    check_root
    check_dependencies
    create_user
    setup_directories
    install_agent
    install_service
    configure_firewall
    setup_log_rotation
    
    # Enable service but don't start yet
    systemctl enable gridpane-monitor
    
    generate_api_key
    
    log "Installation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Start the service: systemctl start gridpane-monitor"
    echo "2. Check status: systemctl status gridpane-monitor"
    echo "3. View logs: journalctl -u gridpane-monitor -f"
    echo "4. Access via SSH tunnel: ssh -L 8847:localhost:8847 user@$(hostname)"
    echo "5. Test endpoint: curl -H 'Content-Type: application/json' -d '{\"api_key\":\"YOUR_API_KEY\"}' http://localhost:8847/api/auth/token"
    echo ""
    echo -e "${YELLOW}Remember: The service only accepts connections from localhost for security.${NC}"
    echo -e "${YELLOW}Use SSH tunneling to access from your iOS app.${NC}"
}

# Run main function
main "$@"
