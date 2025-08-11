#!/bin/bash

# Server Agent System User Setup Script
# Creates dedicated system user and configures sudoers for secure service control

set -e

# Configuration
AGENT_USER="svc-control"
AGENT_GROUP="svc-control"
AGENT_HOME="/opt/server-agent"
SUDOERS_FILE="/etc/sudoers.d/server-agent"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Setting up server agent system user..."

# Create system group if it doesn't exist
if ! getent group "$AGENT_GROUP" > /dev/null 2>&1; then
    log_info "Creating system group: $AGENT_GROUP"
    groupadd --system "$AGENT_GROUP"
else
    log_info "System group $AGENT_GROUP already exists"
fi

# Create system user if it doesn't exist
if ! getent passwd "$AGENT_USER" > /dev/null 2>&1; then
    log_info "Creating system user: $AGENT_USER"
    useradd --system \
        --gid "$AGENT_GROUP" \
        --home-dir "$AGENT_HOME" \
        --create-home \
        --shell /bin/bash \
        --comment "Server Agent Service User" \
        "$AGENT_USER"
else
    log_info "System user $AGENT_USER already exists"
fi

# Create agent home directory structure
log_info "Setting up directory structure..."
mkdir -p "$AGENT_HOME"/{bin,config,logs,ssl}
chown -R "$AGENT_USER:$AGENT_GROUP" "$AGENT_HOME"
chmod 750 "$AGENT_HOME"

# Create log directory
mkdir -p /var/log/server-agent
chown "$AGENT_USER:$AGENT_GROUP" /var/log/server-agent
chmod 750 /var/log/server-agent

# Configure sudoers for limited systemctl access
log_info "Configuring sudoers for service control..."
cat > "$SUDOERS_FILE" << EOF
# Server Agent - Limited systemctl access
# Allow svc-control user to manage specific services only

# Define allowed services
Cmnd_Alias SYSTEMCTL_SERVICES = \\
    /bin/systemctl start nginx, \\
    /bin/systemctl stop nginx, \\
    /bin/systemctl restart nginx, \\
    /bin/systemctl reload nginx, \\
    /bin/systemctl status nginx, \\
    /bin/systemctl is-active nginx, \\
    /bin/systemctl is-enabled nginx, \\
    /bin/systemctl start apache2, \\
    /bin/systemctl stop apache2, \\
    /bin/systemctl restart apache2, \\
    /bin/systemctl reload apache2, \\
    /bin/systemctl status apache2, \\
    /bin/systemctl is-active apache2, \\
    /bin/systemctl is-enabled apache2, \\
    /bin/systemctl start mysql, \\
    /bin/systemctl stop mysql, \\
    /bin/systemctl restart mysql, \\
    /bin/systemctl status mysql, \\
    /bin/systemctl is-active mysql, \\
    /bin/systemctl is-enabled mysql, \\
    /bin/systemctl start mariadb, \\
    /bin/systemctl stop mariadb, \\
    /bin/systemctl restart mariadb, \\
    /bin/systemctl status mariadb, \\
    /bin/systemctl is-active mariadb, \\
    /bin/systemctl is-enabled mariadb, \\
    /bin/systemctl start php8.1-fpm, \\
    /bin/systemctl stop php8.1-fpm, \\
    /bin/systemctl restart php8.1-fpm, \\
    /bin/systemctl reload php8.1-fpm, \\
    /bin/systemctl status php8.1-fpm, \\
    /bin/systemctl is-active php8.1-fpm, \\
    /bin/systemctl is-enabled php8.1-fpm, \\
    /bin/systemctl start php8.2-fpm, \\
    /bin/systemctl stop php8.2-fpm, \\
    /bin/systemctl restart php8.2-fpm, \\
    /bin/systemctl reload php8.2-fpm, \\
    /bin/systemctl status php8.2-fpm, \\
    /bin/systemctl is-active php8.2-fpm, \\
    /bin/systemctl is-enabled php8.2-fpm, \\
    /bin/systemctl start php8.3-fpm, \\
    /bin/systemctl stop php8.3-fpm, \\
    /bin/systemctl restart php8.3-fpm, \\
    /bin/systemctl reload php8.3-fpm, \\
    /bin/systemctl status php8.3-fpm, \\
    /bin/systemctl is-active php8.3-fpm, \\
    /bin/systemctl is-enabled php8.3-fpm, \\
    /bin/systemctl start redis-server, \\
    /bin/systemctl stop redis-server, \\
    /bin/systemctl restart redis-server, \\
    /bin/systemctl status redis-server, \\
    /bin/systemctl is-active redis-server, \\
    /bin/systemctl is-enabled redis-server, \\
    /bin/systemctl start memcached, \\
    /bin/systemctl stop memcached, \\
    /bin/systemctl restart memcached, \\
    /bin/systemctl status memcached, \\
    /bin/systemctl is-active memcached, \\
    /bin/systemctl is-enabled memcached, \\
    /bin/systemctl start supervisor, \\
    /bin/systemctl stop supervisor, \\
    /bin/systemctl restart supervisor, \\
    /bin/systemctl status supervisor, \\
    /bin/systemctl is-active supervisor, \\
    /bin/systemctl is-enabled supervisor

# Allow GridPane CLI access (if available)
Cmnd_Alias GRIDPANE_CLI = /usr/local/bin/gp

# Grant permissions to svc-control user
$AGENT_USER ALL=(root) NOPASSWD: SYSTEMCTL_SERVICES, GRIDPANE_CLI

# Security settings
Defaults:$AGENT_USER !requiretty
Defaults:$AGENT_USER env_reset
Defaults:$AGENT_USER secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

# Validate sudoers file
if visudo -c -f "$SUDOERS_FILE"; then
    log_info "Sudoers configuration validated successfully"
    chmod 440 "$SUDOERS_FILE"
else
    log_error "Sudoers configuration validation failed"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# Test sudo access
log_info "Testing sudo access..."
if sudo -u "$AGENT_USER" sudo -l > /dev/null 2>&1; then
    log_info "Sudo access configured correctly"
else
    log_warn "Sudo access test failed - manual verification may be needed"
fi

# Create systemd service file
log_info "Creating systemd service file..."
cat > /etc/systemd/system/server-agent.service << EOF
[Unit]
Description=Server Agent - Minimal HTTPS API for server control
After=network.target
Wants=network.target

[Service]
Type=simple
User=$AGENT_USER
Group=$AGENT_GROUP
WorkingDirectory=$AGENT_HOME
ExecStart=/usr/bin/node $AGENT_HOME/src/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=server-agent

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$AGENT_HOME /var/log/server-agent /tmp

# Environment
Environment=NODE_ENV=production
Environment=AGENT_USER=$AGENT_USER
Environment=AGENT_HOME=$AGENT_HOME

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

log_info "System user setup completed successfully!"
log_info ""
log_info "Summary:"
log_info "  - System user: $AGENT_USER"
log_info "  - System group: $AGENT_GROUP"
log_info "  - Home directory: $AGENT_HOME"
log_info "  - Log directory: /var/log/server-agent"
log_info "  - Sudoers file: $SUDOERS_FILE"
log_info "  - Systemd service: server-agent.service"
log_info ""
log_info "Next steps:"
log_info "  1. Copy agent files to $AGENT_HOME"
log_info "  2. Configure environment variables"
log_info "  3. Start service: systemctl enable --now server-agent"
