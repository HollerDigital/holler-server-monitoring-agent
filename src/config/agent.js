/**
 * Server Agent Configuration
 * Minimal configuration for server agent mode
 */

const path = require('path');

const agentConfig = {
  // Agent Identity
  agent: {
    id: process.env.AGENT_ID || require('os').hostname(),
    name: process.env.AGENT_NAME || `agent-${require('os').hostname()}`,
    version: '2.1.0',
    mode: 'agent' // vs 'orchestrator'
  },

  // Network Configuration
  server: {
    port: process.env.AGENT_PORT || 3001,
    host: process.env.AGENT_HOST || '127.0.0.1', // localhost only by default
    https: {
      enabled: process.env.AGENT_HTTPS === 'true',
      cert: process.env.AGENT_CERT_PATH || '/etc/ssl/certs/agent.crt',
      key: process.env.AGENT_KEY_PATH || '/etc/ssl/private/agent.key'
    }
  },

  // Security
  security: {
    apiKey: process.env.AGENT_API_KEY || 'change-me-in-production',
    allowedIPs: process.env.AGENT_ALLOWED_IPS?.split(',') || ['127.0.0.1', '::1'],
    rateLimitWindowMs: 15 * 60 * 1000, // 15 minutes
    rateLimitMax: 50 // requests per window
  },

  // System User Configuration
  systemUser: {
    username: process.env.AGENT_USER || 'svc-control',
    group: process.env.AGENT_GROUP || 'svc-control',
    sudoCommands: [
      'systemctl start *',
      'systemctl stop *',
      'systemctl restart *',
      'systemctl reload *',
      'systemctl status *',
      'systemctl is-active *',
      'systemctl is-enabled *'
    ]
  },

  // Services Configuration
  services: {
    controllable: [
      'nginx',
      'apache2',
      'mysql',
      'mariadb',
      'php8.1-fpm',
      'php8.2-fpm',
      'php8.3-fpm',
      'redis-server',
      'memcached',
      'supervisor' // for queue workers
    ],
    // Service aliases for easier management
    aliases: {
      'php-fpm': ['php8.1-fpm', 'php8.2-fpm', 'php8.3-fpm'],
      'database': ['mysql', 'mariadb'],
      'web': ['nginx', 'apache2'],
      'cache': ['redis-server', 'memcached']
    }
  },

  // Orchestrator Communication
  orchestrator: {
    enabled: process.env.ORCHESTRATOR_ENABLED === 'true',
    url: process.env.ORCHESTRATOR_URL || 'https://orchestrator.example.com',
    apiKey: process.env.ORCHESTRATOR_API_KEY,
    heartbeatInterval: parseInt(process.env.HEARTBEAT_INTERVAL) || 30000, // 30 seconds
    timeout: parseInt(process.env.ORCHESTRATOR_TIMEOUT) || 5000 // 5 seconds
  },

  // Logging
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    file: process.env.LOG_FILE || '/var/log/server-agent/agent.log',
    maxFiles: 7,
    maxSize: '10m',
    auditLog: process.env.AUDIT_LOG || '/var/log/server-agent/audit.log'
  },

  // GridPane Integration
  gridpane: {
    enabled: process.env.GRIDPANE_ENABLED !== 'false',
    cliPath: process.env.GP_CLI_PATH || '/usr/local/bin/gp'
  }
};

module.exports = agentConfig;
