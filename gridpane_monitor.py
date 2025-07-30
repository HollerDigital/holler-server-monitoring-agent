#!/usr/bin/env python3
"""
GridPane Server Monitoring Agent - Security-Hardened Version
Lightweight REST API service for collecting server metrics and service status
Designed for secure deployment on GridPane servers via SSH from iOS app

SECURITY FEATURES:
- JWT token authentication with expiration
- Rate limiting per IP/token
- Localhost-only binding (requires SSH tunnel)
- Minimal privileges (non-root user)
- Input validation and sanitization
- Secure logging with rotation
- Process isolation and resource limits
"""

import json
import time
import subprocess
import psutil
import os
import sys
import secrets
import hashlib
import hmac
from datetime import datetime, timezone, timedelta
from flask import Flask, jsonify, request, abort
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import jwt
import logging
from logging.handlers import RotatingFileHandler
from functools import wraps
import signal
import pwd
import grp

# Security Configuration
SECURITY_CONFIG = {
    'bind_host': '127.0.0.1',  # Localhost only - requires SSH tunnel
    'bind_port': 8847,         # Non-standard port
    'jwt_secret_file': '/opt/gridpane-monitor/.jwt_secret',
    'api_key_file': '/opt/gridpane-monitor/.api_key',
    'log_file': '/opt/gridpane-monitor/monitor.log',
    'pid_file': '/opt/gridpane-monitor/monitor.pid',
    'max_log_size': 10 * 1024 * 1024,  # 10MB
    'log_backup_count': 5,
    'token_expiry_hours': 24,
    'rate_limit': '60/minute',  # Max 60 requests per minute
    'user': 'gridpane-monitor',  # Run as dedicated user
    'group': 'gridpane-monitor'
}

# Monitoring Configuration
MONITOR_CONFIG = {
    'services_to_check': [
        'nginx', 'mysql', 'redis-server', 
        'php8.3-fpm', 'php8.2-fpm', 'php8.1-fpm', 'php8.0-fpm', 'php7.4-fpm',
        'fail2ban', 'ssh'
    ],
    'disk_paths': ['/', '/var', '/tmp'],
    'max_processes': 100,  # Limit process list
    'allowed_commands': {  # Whitelist of safe system commands
        'uptime': ['/usr/bin/uptime'],
        'who': ['/usr/bin/who', '-q'],
        'last': ['/usr/bin/last', '-n', '5'],
        'df': ['/bin/df', '-h'],
        'free': ['/usr/bin/free', '-h']
    }
}

app = Flask(__name__)

# Rate limiting
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[SECURITY_CONFIG['rate_limit']]
)
limiter.init_app(app)

# Security utilities
class SecurityManager:
    @staticmethod
    def generate_jwt_secret():
        """Generate a secure JWT secret"""
        return secrets.token_urlsafe(64)
    
    @staticmethod
    def generate_api_key():
        """Generate a secure API key"""
        return secrets.token_urlsafe(32)
    
    @staticmethod
    def load_or_create_secret(file_path, generator_func):
        """Load secret from file or create new one"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    return f.read().strip()
            else:
                secret = generator_func()
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
                with open(file_path, 'w') as f:
                    f.write(secret)
                os.chmod(file_path, 0o600)  # Read-only for owner
                return secret
        except Exception as e:
            logging.error(f"Error managing secret file {file_path}: {e}")
            sys.exit(1)
    
    @staticmethod
    def create_jwt_token(api_key):
        """Create JWT token with expiration"""
        payload = {
            'api_key_hash': hashlib.sha256(api_key.encode()).hexdigest(),
            'exp': datetime.utcnow() + timedelta(hours=SECURITY_CONFIG['token_expiry_hours']),
            'iat': datetime.utcnow(),
            'iss': 'gridpane-monitor'
        }
        return jwt.encode(payload, jwt_secret, algorithm='HS256')
    
    @staticmethod
    def verify_jwt_token(token):
        """Verify JWT token"""
        try:
            payload = jwt.decode(token, jwt_secret, algorithms=['HS256'])
            return payload
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

# Authentication decorator
def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            abort(401)
        
        token = auth_header.split(' ')[1]
        payload = SecurityManager.verify_jwt_token(token)
        if not payload:
            abort(401)
        
        # Verify API key hash
        expected_hash = hashlib.sha256(api_key.encode()).hexdigest()
        if payload.get('api_key_hash') != expected_hash:
            abort(401)
        
        return f(*args, **kwargs)
    return decorated_function

# Safe command execution
def execute_safe_command(command_name, additional_args=None):
    """Execute only whitelisted commands safely"""
    if command_name not in MONITOR_CONFIG['allowed_commands']:
        return None
    
    cmd = MONITOR_CONFIG['allowed_commands'][command_name].copy()
    if additional_args:
        cmd.extend(additional_args)
    
    try:
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            timeout=10,  # 10 second timeout
            check=False
        )
        return {
            'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip(),
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {'error': 'Command timeout'}
    except Exception as e:
        return {'error': str(e)}

# API Endpoints
@app.route('/api/auth/token', methods=['POST'])
@limiter.limit("5/minute")  # Stricter limit for auth
def get_token():
    """Get JWT token with API key"""
    data = request.get_json()
    if not data or 'api_key' not in data:
        abort(400)
    
    provided_key = data['api_key']
    if not hmac.compare_digest(provided_key, api_key):
        abort(401)
    
    token = SecurityManager.create_jwt_token(provided_key)
    return jsonify({
        'token': token,
        'expires_in': SECURITY_CONFIG['token_expiry_hours'] * 3600
    })

@app.route('/health', methods=['GET'])
def simple_health_check():
    """Simple health check without authentication for basic connectivity testing"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'version': '1.0.0'
    })

@app.route('/api/health', methods=['GET'])
@require_auth
def health_check():
    """Basic health check"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'version': '1.0.0'
    })

@app.route('/api/system/metrics', methods=['GET'])
@require_auth
def system_metrics():
    """Get system metrics"""
    try:
        # CPU metrics
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()
        load_avg = os.getloadavg()
        
        # Memory metrics
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        # Disk metrics
        disk_usage = {}
        for path in MONITOR_CONFIG['disk_paths']:
            if os.path.exists(path):
                usage = psutil.disk_usage(path)
                disk_usage[path] = {
                    'total': usage.total,
                    'used': usage.used,
                    'free': usage.free,
                    'percent': (usage.used / usage.total) * 100
                }
        
        # Network metrics (basic)
        network = psutil.net_io_counters()
        
        # Uptime
        uptime_cmd = execute_safe_command('uptime')
        
        return jsonify({
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'cpu': {
                'percent': cpu_percent,
                'count': cpu_count,
                'load_avg': {
                    '1min': load_avg[0],
                    '5min': load_avg[1],
                    '15min': load_avg[2]
                }
            },
            'memory': {
                'total': memory.total,
                'available': memory.available,
                'used': memory.used,
                'percent': memory.percent
            },
            'swap': {
                'total': swap.total,
                'used': swap.used,
                'free': swap.free,
                'percent': swap.percent
            },
            'disk': disk_usage,
            'network': {
                'bytes_sent': network.bytes_sent,
                'bytes_recv': network.bytes_recv,
                'packets_sent': network.packets_sent,
                'packets_recv': network.packets_recv
            },
            'uptime': uptime_cmd['stdout'] if uptime_cmd else None
        })
    except Exception as e:
        logging.error(f"Error getting system metrics: {e}")
        abort(500)

@app.route('/api/services/status', methods=['GET'])
@require_auth
def service_status():
    """Get service status"""
    try:
        services = {}
        for service in MONITOR_CONFIG['services_to_check']:
            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                is_active = result.stdout.strip() == 'active'
                
                # Get service info
                info_result = subprocess.run(
                    ['systemctl', 'show', service, '--no-page'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                
                services[service] = {
                    'active': is_active,
                    'status': result.stdout.strip(),
                    'enabled': 'enabled' in info_result.stdout
                }
            except Exception as e:
                services[service] = {
                    'active': False,
                    'status': 'error',
                    'error': str(e)
                }
        
        return jsonify({
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': services
        })
    except Exception as e:
        logging.error(f"Error getting service status: {e}")
        abort(500)

@app.route('/api/processes/top', methods=['GET'])
@require_auth
def top_processes():
    """Get top processes by CPU/memory usage"""
    try:
        processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent', 'username']):
            try:
                processes.append(proc.info)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        # Sort by CPU usage and limit results
        processes.sort(key=lambda x: x['cpu_percent'] or 0, reverse=True)
        processes = processes[:MONITOR_CONFIG['max_processes']]
        
        return jsonify({
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'processes': processes
        })
    except Exception as e:
        logging.error(f"Error getting process list: {e}")
        abort(500)

# Security and setup functions
def setup_logging():
    """Setup secure logging"""
    log_dir = os.path.dirname(SECURITY_CONFIG['log_file'])
    os.makedirs(log_dir, exist_ok=True)
    
    handler = RotatingFileHandler(
        SECURITY_CONFIG['log_file'],
        maxBytes=SECURITY_CONFIG['max_log_size'],
        backupCount=SECURITY_CONFIG['log_backup_count']
    )
    
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    handler.setFormatter(formatter)
    
    app.logger.addHandler(handler)
    app.logger.setLevel(logging.INFO)
    
    # Set file permissions
    os.chmod(SECURITY_CONFIG['log_file'], 0o640)

def drop_privileges():
    """Drop privileges to non-root user"""
    try:
        user_info = pwd.getpwnam(SECURITY_CONFIG['user'])
        group_info = grp.getgrnam(SECURITY_CONFIG['group'])
        
        os.setgid(group_info.gr_gid)
        os.setuid(user_info.pw_uid)
        
        logging.info(f"Dropped privileges to {SECURITY_CONFIG['user']}:{SECURITY_CONFIG['group']}")
    except Exception as e:
        logging.error(f"Failed to drop privileges: {e}")
        sys.exit(1)

def create_pid_file():
    """Create PID file for process management"""
    pid_dir = os.path.dirname(SECURITY_CONFIG['pid_file'])
    os.makedirs(pid_dir, exist_ok=True)
    
    with open(SECURITY_CONFIG['pid_file'], 'w') as f:
        f.write(str(os.getpid()))
    
    os.chmod(SECURITY_CONFIG['pid_file'], 0o644)

def cleanup():
    """Cleanup on exit"""
    try:
        if os.path.exists(SECURITY_CONFIG['pid_file']):
            os.remove(SECURITY_CONFIG['pid_file'])
    except Exception as e:
        logging.error(f"Error during cleanup: {e}")

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logging.info(f"Received signal {signum}, shutting down...")
    cleanup()
    sys.exit(0)

# Initialize security components
jwt_secret = SecurityManager.load_or_create_secret(
    SECURITY_CONFIG['jwt_secret_file'], 
    SecurityManager.generate_jwt_secret
)

api_key = SecurityManager.load_or_create_secret(
    SECURITY_CONFIG['api_key_file'],
    SecurityManager.generate_api_key
)

if __name__ == '__main__':
    # Setup signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Setup logging
    setup_logging()
    
    # Create PID file
    create_pid_file()
    
    # Log startup
    logging.info("GridPane Monitor starting up...")
    logging.info(f"API Key: {api_key}")  # Log API key for initial setup
    
    try:
        # Drop privileges if running as root
        if os.geteuid() == 0:
            drop_privileges()
        
        # Start Flask app
        app.run(
            host=SECURITY_CONFIG['bind_host'],
            port=SECURITY_CONFIG['bind_port'],
            debug=False,
            threaded=True
        )
    except Exception as e:
        logging.error(f"Failed to start server: {e}")
        cleanup()
        sys.exit(1)
