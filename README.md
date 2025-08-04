# GridPane Manager Backend API

Apple-friendly, App Store-compliant backend service for the GridPane Manager iOS app. This Node.js API handles all privileged server operations, monitoring, and notifications without requiring direct SSH access from the mobile app.

**🚀 MAJOR UPDATE:** Upgraded from Python Flask to Node.js Express for better iOS integration, enhanced security, and improved performance.

## Features

- **System Metrics**: CPU usage, memory usage, disk space, network statistics
- **Service Monitoring**: Track critical services and processes
- **REST API**: Provides metrics via HTTP endpoints for remote monitoring
- **GridPane Integration**: Designed specifically for GridPane server environments
- **Systemd Service**: Runs as a background service with automatic startup
- **Lightweight**: Minimal resource footprint and dependencies

## Installation

### Automatic Installation

Run the installation script on your GridPane server:

```bash
cd /tmp
git clone https://github.com/HollerDigital/holler-server-monitoring-agent.git
cd holler-server-monitoring-agent
chmod +x install.sh
sudo ./install.sh
```

### Manual Installation

1. Copy `gridpane_monitor.py` to `/opt/gridpane-monitor/`
2. Copy `gridpane-monitor.service` to `/etc/systemd/system/`
3. Install Python dependencies: `pip3 install psutil requests`
4. Enable and start the service:
   ```bash
   sudo systemctl enable gridpane-monitor
   sudo systemctl start gridpane-monitor
   ```

## Configuration

The monitoring agent runs on port 8080 by default and provides the following endpoints:

- `GET /health` - Health check endpoint
- `GET /metrics` - System metrics (CPU, memory, disk, network)
- `GET /services` - Service status monitoring

## API Endpoints

### Health Check
```bash
curl http://localhost:8080/api/health
```

### System Metrics
```bash
curl http://localhost:8080/metrics
```

Response format:
```json
{
  "timestamp": "2025-07-30T15:37:00Z",
  "cpu_percent": 15.2,
  "memory_percent": 45.8,
  "disk_usage": {
    "/": {"used_percent": 67.3, "free_gb": 12.5}
  },
  "network": {
    "bytes_sent": 1024000,
    "bytes_recv": 2048000
  }
}
```

## Uninstallation

To remove the monitoring agent:

```bash
cd /tmp/holler-server-monitoring-agent
sudo ./uninstall.sh
```

## Requirements

- Python 3.6+
- psutil library
- requests library
- systemd (for service management)
- GridPane server environment

## License

MIT License - see LICENSE file for details.

## Support

For support and issues, please contact Holler Digital or create an issue in this repository.
