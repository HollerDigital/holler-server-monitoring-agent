#!/bin/bash
set -euo pipefail

# Holler Agent Uninstall Script
# Completely removes the agent and all associated files

echo "🗑️ Holler Agent Uninstall Script"
echo "================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)" 
   exit 1
fi

# Confirmation prompt
read -p "⚠️  This will completely remove the Holler Agent. Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Uninstall cancelled"
    exit 1
fi

echo "🛑 Stopping Holler Agent service..."
if systemctl is-active --quiet holler-agent 2>/dev/null; then
    systemctl stop holler-agent
    echo "✅ Service stopped"
else
    echo "ℹ️  Service was not running"
fi

echo "🔧 Disabling Holler Agent service..."
if systemctl is-enabled --quiet holler-agent 2>/dev/null; then
    systemctl disable holler-agent
    echo "✅ Service disabled"
else
    echo "ℹ️  Service was not enabled"
fi

echo "📋 Removing systemd service file..."
if [ -f "/etc/systemd/system/holler-agent.service" ]; then
    rm -f /etc/systemd/system/holler-agent.service
    systemctl daemon-reload
    echo "✅ Service file removed"
else
    echo "ℹ️  Service file not found"
fi

echo "📁 Removing application directory..."
if [ -d "/opt/holler-agent" ]; then
    rm -rf /opt/holler-agent
    echo "✅ Application directory removed"
else
    echo "ℹ️  Application directory not found"
fi

echo "📁 Removing configuration directory..."
if [ -d "/etc/holler-agent" ]; then
    rm -rf /etc/holler-agent
    echo "✅ Configuration directory removed"
else
    echo "ℹ️  Configuration directory not found"
fi

echo "📁 Removing log directory..."
if [ -d "/var/log/holler-agent" ]; then
    rm -rf /var/log/holler-agent
    echo "✅ Log directory removed"
else
    echo "ℹ️  Log directory not found"
fi

echo "👤 Removing system user..."
if id "holler-agent" &>/dev/null; then
    userdel holler-agent 2>/dev/null || true
    echo "✅ System user removed"
else
    echo "ℹ️  System user not found"
fi

echo "🔐 Removing sudoers configuration..."
if [ -f "/etc/sudoers.d/holler-agent" ]; then
    rm -f /etc/sudoers.d/holler-agent
    echo "✅ Sudoers configuration removed"
else
    echo "ℹ️  Sudoers configuration not found"
fi

echo "🧹 Cleaning up temporary files..."
rm -rf /tmp/holler-agent-* 2>/dev/null || true

echo ""
echo "✅ Holler Agent completely uninstalled!"
echo ""
echo "📋 Summary:"
echo "  • Service stopped and disabled"
echo "  • All files and directories removed"
echo "  • System user deleted"
echo "  • Sudoers configuration removed"
echo ""
echo "ℹ️  The agent has been revoked from the manager automatically"
echo "   (if it was properly registered)"
