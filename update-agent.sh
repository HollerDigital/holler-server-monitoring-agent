#!/bin/bash
set -euo pipefail

# Holler Agent Update Script
# Updates the agent to the latest version while preserving configuration

echo "🔄 Holler Agent Update Script"
echo "============================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)" 
   exit 1
fi

# Check if agent is installed
if [ ! -d "/opt/holler-agent" ]; then
    echo "❌ Holler Agent is not installed"
    echo "   Run the install script first: curl -sSL install-agent.sh | sudo bash"
    exit 1
fi

# Check if service exists
if [ ! -f "/etc/systemd/system/holler-agent.service" ]; then
    echo "❌ Holler Agent service not found"
    exit 1
fi

echo "📋 Current agent status:"
systemctl status holler-agent --no-pager -l || true

echo ""
echo "⬇️ Downloading latest agent code..."
cd /tmp
if [ -d "holler-server-monitoring-agent" ]; then
    rm -rf holler-server-monitoring-agent
fi
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent

echo "🛑 Stopping agent service..."
systemctl stop holler-agent

echo "💾 Backing up current configuration..."
cp /opt/holler-agent/.env /tmp/holler-agent-env-backup-$(date +%Y%m%d-%H%M%S)
cp -r /etc/holler-agent /tmp/holler-agent-config-backup-$(date +%Y%m%d-%H%M%S)

echo "📋 Installing updated agent files..."
# Preserve ownership while updating files
cp -r src/* /opt/holler-agent/src/
cp package.json /opt/holler-agent/
chown -R holler-agent:holler-agent /opt/holler-agent

echo "📦 Updating dependencies..."
cd /opt/holler-agent
sudo -u holler-agent npm install --production

echo "🔧 Updating systemd service if needed..."
if ! cmp -s /tmp/holler-server-monitoring-agent/scripts/holler-agent.service /etc/systemd/system/holler-agent.service; then
    echo "  • Service file has updates, applying..."
    cp /tmp/holler-server-monitoring-agent/scripts/holler-agent.service /etc/systemd/system/
    systemctl daemon-reload
else
    echo "  • Service file unchanged"
fi

echo "🚀 Starting updated agent..."
systemctl start holler-agent

# Wait a moment for startup
sleep 3

echo "✅ Checking agent status..."
if systemctl is-active --quiet holler-agent; then
    echo "✅ Agent updated successfully and is running"
    
    # Get version info
    AGENT_VERSION=$(curl -s http://127.0.0.1:3001/health 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
    echo "📋 Agent version: $AGENT_VERSION"
    
    echo ""
    echo "📋 Update Summary:"
    echo "  • Agent code updated to latest version"
    echo "  • Dependencies updated"
    echo "  • Configuration preserved"
    echo "  • Service restarted successfully"
    echo ""
    echo "🧹 Cleaning up..."
    rm -rf /tmp/holler-server-monitoring-agent
    
else
    echo "❌ Agent failed to start after update"
    echo "📋 Service status:"
    systemctl status holler-agent --no-pager -l
    echo ""
    echo "📋 Recent logs:"
    journalctl -u holler-agent -n 20 --no-pager
    echo ""
    echo "🔄 You may need to restore from backup:"
    echo "   Backup files are in /tmp/holler-agent-*-backup-*"
    exit 1
fi
