#!/bin/bash
set -euo pipefail

# GridPane Monitoring Agent - Secure Uninstall Script
# This script safely removes the monitoring agent and cleans up all components

INSTALL_DIR="/opt/gridpane-monitor"
SERVICE_FILE="/etc/systemd/system/gridpane-monitor.service"
USER_NAME="gridpane-monitor"
GROUP_NAME="gridpane-monitor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

stop_service() {
    log "Stopping GridPane monitoring service..."
    
    if systemctl is-active --quiet gridpane-monitor; then
        systemctl stop gridpane-monitor
        log "Service stopped"
    else
        log "Service was not running"
    fi
    
    if systemctl is-enabled --quiet gridpane-monitor; then
        systemctl disable gridpane-monitor
        log "Service disabled"
    fi
}

remove_service() {
    log "Removing systemd service..."
    
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        log "Service file removed"
    else
        log "Service file not found"
    fi
}

backup_data() {
    log "Creating backup of configuration and logs..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        BACKUP_DIR="/tmp/gridpane-monitor-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Backup API key and JWT secret (but not logs for security)
        if [[ -f "$INSTALL_DIR/.api_key" ]]; then
            cp "$INSTALL_DIR/.api_key" "$BACKUP_DIR/"
        fi
        if [[ -f "$INSTALL_DIR/.jwt_secret" ]]; then
            cp "$INSTALL_DIR/.jwt_secret" "$BACKUP_DIR/"
        fi
        
        log "Backup created at: $BACKUP_DIR"
        echo "You can restore these files if you reinstall the agent later."
    fi
}

remove_files() {
    log "Removing installation directory..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log "Installation directory removed"
    else
        log "Installation directory not found"
    fi
}

remove_user() {
    log "Removing dedicated user and group..."
    
    # Remove user if it exists
    if getent passwd "$USER_NAME" > /dev/null 2>&1; then
        userdel "$USER_NAME"
        log "Removed user: $USER_NAME"
    else
        log "User $USER_NAME not found"
    fi
    
    # Remove group if it exists and has no other members
    if getent group "$GROUP_NAME" > /dev/null 2>&1; then
        groupdel "$GROUP_NAME" 2>/dev/null || warn "Could not remove group $GROUP_NAME (may have other members)"
    else
        log "Group $GROUP_NAME not found"
    fi
}

remove_log_rotation() {
    log "Removing log rotation configuration..."
    
    if [[ -f "/etc/logrotate.d/gridpane-monitor" ]]; then
        rm -f "/etc/logrotate.d/gridpane-monitor"
        log "Log rotation configuration removed"
    else
        log "Log rotation configuration not found"
    fi
}

cleanup_logs() {
    log "Cleaning up system logs..."
    
    # Clear systemd journal entries for this service
    journalctl --vacuum-time=1s --unit=gridpane-monitor 2>/dev/null || true
    
    log "System logs cleaned"
}

main() {
    log "Starting GridPane Monitoring Agent uninstallation..."
    
    check_root
    
    # Confirm uninstallation
    echo -e "${YELLOW}This will completely remove the GridPane Monitoring Agent.${NC}"
    echo -e "${YELLOW}All configuration files and logs will be deleted.${NC}"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Uninstallation cancelled"
        exit 0
    fi
    
    stop_service
    remove_service
    backup_data
    remove_files
    remove_user
    remove_log_rotation
    cleanup_logs
    
    log "Uninstallation completed successfully!"
    echo ""
    echo "The GridPane Monitoring Agent has been completely removed."
    echo "Backup files (if any) are stored in /tmp/gridpane-monitor-backup-*"
    echo ""
}

# Run main function
main "$@"
