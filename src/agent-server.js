/**
 * Server Agent - Minimal HTTPS API
 * Secure localhost-only server for system control operations
 */

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const https = require('https');
const fs = require('fs');
require('dotenv').config();

const logger = require('./utils/logger');
const agentConfig = require('./config/agent');
const controlRoutes = require('./routes/control');
const monitoringRoutes = require('./routes/monitoring');
const diagnosticsRoutes = require('./routes/diagnostics');

const app = express();

// Agent-specific middleware
app.use(helmet({
  // More restrictive headers for agent mode
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'none'"],
      styleSrc: ["'none'"],
      imgSrc: ["'none'"]
    }
  }
}));

// CORS - restrictive for agent mode
app.use(cors({
  origin: agentConfig.security.allowedIPs.map(ip => `http://${ip}:*`).concat(
    agentConfig.security.allowedIPs.map(ip => `https://${ip}:*`)
  ),
  credentials: false // No cookies needed for agent
}));

// Rate limiting - more restrictive for agent
const limiter = rateLimit({
  windowMs: agentConfig.security.rateLimitWindowMs,
  max: agentConfig.security.rateLimitMax,
  message: {
    error: 'Rate limit exceeded',
    message: 'Too many requests from this IP, please try again later.',
    retryAfter: Math.ceil(agentConfig.security.rateLimitWindowMs / 1000)
  },
  standardHeaders: true,
  legacyHeaders: false
});
app.use(limiter);

// Body parsing middleware
app.use(express.json({ limit: '1mb' })); // Smaller limit for agent
app.use(express.urlencoded({ extended: true }));

// Request logging with agent context
app.use((req, res, next) => {
  logger.info(`[AGENT] ${req.method} ${req.path}`, {
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    agentId: agentConfig.agent.id
  });
  next();
});

// Simple API key authentication for agent
const authenticateAgent = (req, res, next) => {
  const apiKey = req.get('X-API-Key') || req.get('Authorization')?.replace('Bearer ', '');
  
  if (!apiKey || apiKey !== agentConfig.security.apiKey) {
    logger.warn(`[AGENT] Unauthorized access attempt`, {
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      hasApiKey: !!apiKey
    });
    
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Valid API key required'
    });
  }
  
  next();
};

// Health check endpoint (no auth required)
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    agent: {
      id: agentConfig.agent.id,
      name: agentConfig.agent.name,
      version: agentConfig.agent.version,
      mode: agentConfig.agent.mode
    },
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Agent info endpoint (no auth required)
app.get('/agent/info', (req, res) => {
  res.json({
    agent: {
      id: agentConfig.agent.id,
      name: agentConfig.agent.name,
      version: agentConfig.agent.version,
      mode: agentConfig.agent.mode
    },
    capabilities: {
      services: agentConfig.services.controllable,
      aliases: Object.keys(agentConfig.services.aliases),
      gridpane: agentConfig.gridpane.enabled
    },
    security: {
      httpsEnabled: agentConfig.server.https.enabled,
      rateLimitWindow: agentConfig.security.rateLimitWindowMs,
      rateLimitMax: agentConfig.security.rateLimitMax
    },
    timestamp: new Date().toISOString()
  });
});

// Protected routes (require API key)
app.use('/api/control', authenticateAgent, controlRoutes);
app.use('/api/monitoring', authenticateAgent, monitoringRoutes);
app.use('/api/diagnostics', authenticateAgent, diagnosticsRoutes);

// Agent-specific endpoints
app.get('/api/agent/status', authenticateAgent, (req, res) => {
  res.json({
    success: true,
    agent: {
      id: agentConfig.agent.id,
      name: agentConfig.agent.name,
      version: agentConfig.agent.version,
      mode: agentConfig.agent.mode,
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      pid: process.pid
    },
    system: {
      hostname: require('os').hostname(),
      platform: process.platform,
      arch: process.arch,
      nodeVersion: process.version
    },
    timestamp: new Date().toISOString()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('[AGENT] Unhandled error:', {
    error: err.message,
    stack: err.stack,
    ip: req.ip,
    path: req.path
  });
  
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong',
    agentId: agentConfig.agent.id
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not found',
    message: 'The requested endpoint does not exist',
    agentId: agentConfig.agent.id
  });
});

// Start server (HTTP or HTTPS)
const startServer = () => {
  const { port, host, https: httpsConfig } = agentConfig.server;
  
  if (httpsConfig.enabled) {
    // HTTPS server
    try {
      const options = {
        key: fs.readFileSync(httpsConfig.key),
        cert: fs.readFileSync(httpsConfig.cert)
      };
      
      const server = https.createServer(options, app);
      server.listen(port, host, () => {
        logger.info(`[AGENT] HTTPS Server started`, {
          port,
          host,
          agentId: agentConfig.agent.id,
          version: agentConfig.agent.version
        });
      });
      
      return server;
    } catch (error) {
      logger.error('[AGENT] Failed to start HTTPS server:', error);
      logger.info('[AGENT] Falling back to HTTP server');
    }
  }
  
  // HTTP server (fallback or default)
  const server = app.listen(port, host, () => {
    logger.info(`[AGENT] HTTP Server started`, {
      port,
      host,
      agentId: agentConfig.agent.id,
      version: agentConfig.agent.version,
      mode: 'agent'
    });
  });
  
  return server;
};

const server = startServer();

// Graceful shutdown
const shutdown = (signal) => {
  logger.info(`[AGENT] ${signal} received, shutting down gracefully`);
  
  server.close(() => {
    logger.info('[AGENT] Server closed');
    process.exit(0);
  });
  
  // Force close after 10 seconds
  setTimeout(() => {
    logger.error('[AGENT] Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;
