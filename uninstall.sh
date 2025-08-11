#!/bin/bash

# GridPane Manager Backend Uninstall Script
# Completely removes the GridPane Manager backend agent from the system

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="gridpane-manager"
SERVICE_USER="gridpane-manager"
APP_DIR="/opt/gridpane-manager"
CONFIG_DIR="/etc/gridpane-manager"
LOG_DIR="/var/log/gridpane-manager"

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}                    GridPane Manager Backend Uninstaller${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}This will completely remove the GridPane Manager backend agent from your system.${NC}"
echo
echo -e "${RED}The following will be removed:${NC}"
echo -e "  • Service: $SERVICE_NAME"
echo -e "  • User: $SERVICE_USER"
echo -e "  • Application directory: $APP_DIR"
echo -e "  • Configuration directory: $CONFIG_DIR"
echo -e "  • Log directory: $LOG_DIR"
echo -e "  • Systemd service file"
echo -e "  • Logrotate configuration"
echo -e "  • Sudo permissions"
echo
read -p "$(echo -e "${YELLOW}Are you sure you want to continue? (y/N): ${NC}")" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Uninstall cancelled."
    exit 0
fi

echo
print_info "Starting uninstall process..."

# Stop and disable the service
if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
    echo -e "${YELLOW}Stopping service...${NC}"
    systemctl stop $SERVICE_NAME
    print_status "Service stopped"
else
    print_info "Service is not running"
fi

if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
    echo -e "${YELLOW}Disabling service...${NC}"
    systemctl disable $SERVICE_NAME
    print_status "Service disabled"
else
    print_info "Service is not enabled"
fi

# Remove systemd service file
if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    echo -e "${YELLOW}Removing systemd service file...${NC}"
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    print_status "Systemd service file removed"
else
    print_info "Systemd service file not found"
fi

# Remove logrotate configuration
if [ -f "/etc/logrotate.d/$SERVICE_NAME" ]; then
    echo -e "${YELLOW}Removing logrotate configuration...${NC}"
    rm -f "/etc/logrotate.d/$SERVICE_NAME"
    print_status "Logrotate configuration removed"
else
    print_info "Logrotate configuration not found"
fi

# Remove sudo permissions
if [ -f "/etc/sudoers.d/$SERVICE_NAME" ]; then
    echo -e "${YELLOW}Removing sudo permissions...${NC}"
    rm -f "/etc/sudoers.d/$SERVICE_NAME"
    print_status "Sudo permissions removed"
else
    print_info "Sudo permissions file not found"
fi

# Remove application directory
if [ -d "$APP_DIR" ]; then
    echo -e "${YELLOW}Removing application directory...${NC}"
    rm -rf "$APP_DIR"
    print_status "Application directory removed"
else
    print_info "Application directory not found"
fi

# Remove configuration directory
if [ -d "$CONFIG_DIR" ]; then
    echo -e "${YELLOW}Removing configuration directory...${NC}"
    # Ask if user wants to keep configuration for reinstall
    read -p "$(echo -e "${YELLOW}Keep configuration files for potential reinstall? (y/N): ${NC}")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        print_status "Configuration directory removed"
    else
        print_warning "Configuration directory preserved at $CONFIG_DIR"
        print_info "Contains: API keys, server configuration, and environment settings"
    fi
else
    print_info "Configuration directory not found"
fi

# Remove log directory
if [ -d "$LOG_DIR" ]; then
    echo -e "${YELLOW}Removing log directory...${NC}"
    rm -rf "$LOG_DIR"
    print_status "Log directory removed"
else
    print_info "Log directory not found"
fi

# Remove service user
if id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Removing service user...${NC}"
    userdel "$SERVICE_USER" 2>/dev/null || print_warning "Could not remove user $SERVICE_USER (may be in use)"
    print_status "Service user removal attempted"
else
    print_info "Service user not found"
fi

# Remove any remaining systemd overrides
OVERRIDE_DIR="/etc/systemd/system/$SERVICE_NAME.service.d"
if [ -d "$OVERRIDE_DIR" ]; then
    echo -e "${YELLOW}Removing systemd overrides...${NC}"
    rm -rf "$OVERRIDE_DIR"
    systemctl daemon-reload
    print_status "Systemd overrides removed"
fi

# Clean up any Node.js processes (if any are still running)
if pgrep -f "gridpane-manager" > /dev/null; then
    echo -e "${YELLOW}Killing any remaining processes...${NC}"
    pkill -f "gridpane-manager" || true
    print_status "Remaining processes terminated"
fi

# Final cleanup
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                    Uninstall Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
print_status "GridPane Manager backend agent has been completely removed"

if [ -d "$CONFIG_DIR" ]; then
    echo
    print_info "Configuration preserved for reinstall:"
    print_info "  • Location: $CONFIG_DIR"
    print_info "  • To reinstall with same settings, run the installer again"
    print_info "  • To completely remove config: sudo rm -rf $CONFIG_DIR"
fi

echo
print_info "To reinstall, run:"
print_info "  curl -fsSL https://raw.githubusercontent.com/HollerDigital/holler-server-monitoring-agent/main/install.sh | sudo bash"
echo
print_info "Or for interactive installation:"
print_info "  git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git"
print_info "  cd holler-server-monitoring-agent"
print_info "  sudo bash install.sh"
echo

exit 0
