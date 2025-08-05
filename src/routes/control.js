/**
 * Control Routes
 * Server control endpoints for service restarts, cache clearing, etc.
 */

const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const { body, validationResult } = require('express-validator');
const logger = require('../utils/logger');

const router = express.Router();
const execAsync = promisify(exec);

/**
 * POST /api/control/restart/nginx
 * Restart Nginx - Stage 2 (Coming Soon)
 */
router.post('/restart/nginx', async (req, res) => {
  res.status(501).json({
    success: false,
    message: 'Nginx restart - Stage 2 feature (Coming Soon)',
    note: 'This feature requires proper GridPane system user authentication and will be available in Stage 2',
    timestamp: new Date().toISOString()
  });
});

/**
 * POST /api/control/restart/mysql
 * Restart MySQL database server
 */
router.post('/restart/mysql', async (req, res) => {
  res.status(501).json({
    success: false,
    message: 'MySQL restart - Stage 2 feature (Coming Soon)',
    note: 'This feature requires proper GridPane system user authentication and will be available in Stage 2',
    timestamp: new Date().toISOString()
  });
});

/**
 * POST /api/control/restart/server
 * Restart the entire server (use with caution)
 */
router.post('/restart/server', [
  body('confirm').equals('yes').withMessage('Must confirm server restart with "yes"')
], async (req, res) => {
  try {
    // Validate confirmation
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        error: 'Confirmation required',
        message: 'Must confirm server restart with "yes"'
      });
    }

    logger.logSystemEvent('SERVER_RESTART_REQUESTED', { ip: req.ip, user: req.user?.id });

    // Send response before restarting (connection will be lost)
    res.json({
      success: true,
      message: 'Server restart initiated - connection will be lost',
      timestamp: new Date().toISOString()
    });

    // Schedule restart in 5 seconds to allow response to be sent
    setTimeout(async () => {
      try {
        logger.logSystemEvent('SERVER_RESTART_EXECUTING', { ip: req.ip, user: req.user?.id });
        await execAsync('sudo shutdown -r +1 "Server restart requested via GridPane Manager API"');
      } catch (error) {
        logger.error('Server restart failed:', error);
      }
    }, 5000);

  } catch (error) {
    logger.error('Server restart failed:', error);
    logger.logSystemEvent('SERVER_RESTART_FAILED', { 
      error: error.message, 
      ip: req.ip, 
      user: req.user?.id 
    });

    res.status(500).json({
      error: 'Failed to restart server',
      message: error.message
    });
  }
});

/**
 * POST /api/control/cache/clear
 * Clear all sites cache using GridPane CLI with enhanced debugging
 */
router.post('/cache/clear', async (req, res) => {
  const startTime = Date.now();
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    // Enhanced request logging
    logger.info(`[${requestId}] Cache clear requested`, {
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      method: req.method,
      url: req.originalUrl,
      timestamp: new Date().toISOString()
    });
    
    // Log request headers for debugging
    logger.info(`[${requestId}] Request headers:`, {
      'content-type': req.get('Content-Type'),
      'x-api-key': req.get('X-API-Key') ? '[PRESENT]' : '[MISSING]',
      'user-agent': req.get('User-Agent'),
      'host': req.get('Host')
    });
    
    logger.logSystemEvent('CACHE_CLEAR_REQUESTED', { 
      requestId,
      ip: req.ip, 
      user: req.user?.id
    });

    // Check if GridPane CLI is available
    logger.info(`[${requestId}] Checking GridPane CLI availability`);
    await execAsync('which gp');
    logger.info(`[${requestId}] GridPane CLI found at /usr/local/bin/gp');
    
    // Clear all caches using GridPane CLI
    logger.info(`[${requestId}] Executing: gp fix cached`);
    const execStart = Date.now();
    const { stdout, stderr } = await execAsync('gp fix cached');
    const execDuration = Date.now() - execStart;
    
    logger.info(`[${requestId}] GridPane CLI execution completed`, {
      duration: `${execDuration}ms`,
      stdoutLength: stdout.length,
      stderrLength: stderr.length,
      hasErrors: stderr.length > 0
    });
    
    // Log detailed output for debugging
    if (stdout) {
      logger.info(`[${requestId}] STDOUT:`, stdout);
    }
    if (stderr) {
      logger.warn(`[${requestId}] STDERR:`, stderr);
    }

    const totalDuration = Date.now() - startTime;
    logger.logSystemEvent('CACHE_CLEAR_SUCCESS', { 
      requestId,
      method: 'gridpane-cli',
      duration: `${totalDuration}ms`,
      ip: req.ip, 
      user: req.user?.id 
    });

    const response = {
      success: true,
      message: 'Cache cleared successfully',
      output: stdout,
      stderr: stderr || null,
      duration: `${totalDuration}ms`,
      requestId,
      timestamp: new Date().toISOString(),
      debug: {
        cliExecutionTime: `${execDuration}ms`,
        totalRequestTime: `${totalDuration}ms`,
        outputSize: stdout.length,
        hasWarnings: stderr.length > 0,
        command: 'gp fix cached'
      }
    };

    // Log response details
    logger.info(`[${requestId}] Response prepared`, {
      responseSize: JSON.stringify(response).length,
      duration: `${totalDuration}ms`,
      success: true
    });

    // Set response headers for debugging
    res.set({
      'X-Request-ID': requestId,
      'X-Execution-Time': `${totalDuration}ms`,
      'X-CLI-Execution-Time': `${execDuration}ms`
    });

    res.json(response);

  } catch (error) {
    const totalDuration = Date.now() - startTime;
    
    logger.error(`[${requestId}] Cache clear failed:`, {
      error: error.message,
      stack: error.stack,
      duration: `${totalDuration}ms`,
      ip: req.ip
    });
    
    logger.logSystemEvent('CACHE_CLEAR_FAILED', { 
      requestId,
      error: error.message, 
      duration: `${totalDuration}ms`,
      ip: req.ip, 
      user: req.user?.id 
    });

    const errorResponse = {
      success: false,
      error: 'Failed to clear cache',
      message: error.message,
      requestId,
      duration: `${totalDuration}ms`,
      timestamp: new Date().toISOString(),
      debug: {
        errorType: error.constructor.name,
        totalRequestTime: `${totalDuration}ms`,
        command: 'gp fix cached'
      }
    };

    // Set error response headers
    res.set({
      'X-Request-ID': requestId,
      'X-Execution-Time': `${totalDuration}ms`,
      'X-Error-Type': error.constructor.name
    });

    res.status(500).json(errorResponse);
  }
});

/**
 * POST /api/control/cache/clear-site
 * Clear cache for a specific site
 */
router.post('/cache/clear-site', [
  body('site').notEmpty().withMessage('Site name is required')
], async (req, res) => {
  try {
    // Validate input
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        error: 'Validation failed',
        details: errors.array()
      });
    }

    const { site } = req.body;
    logger.logSystemEvent('SITE_CACHE_CLEAR_REQUESTED', { 
      site, 
      ip: req.ip, 
      user: req.user?.id 
    });

    // Clear cache for specific site using GridPane CLI
    const { stdout, stderr } = await execAsync(`gp site ${site} cache clear`);

    logger.logSystemEvent('SITE_CACHE_CLEAR_SUCCESS', { 
      site,
      output: stdout,
      ip: req.ip, 
      user: req.user?.id 
    });

    res.json({
      success: true,
      message: `Cache cleared successfully for site: ${site}`,
      output: stdout,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Site cache clear failed:', error);
    logger.logSystemEvent('SITE_CACHE_CLEAR_FAILED', { 
      site: req.body.site,
      error: error.message, 
      ip: req.ip, 
      user: req.user?.id 
    });

    res.status(500).json({
      error: 'Failed to clear site cache',
      message: error.message
    });
  }
});

/**
 * GET /api/control/services/status
 * Get status of all controllable services
 */
router.get('/services/status', async (req, res) => {
  try {
    const services = ['nginx', 'mysql', 'apache2', 'php8.1-fpm', 'redis-server', 'memcached'];
    const serviceStatus = {};

    for (const service of services) {
      try {
        await execAsync(`systemctl is-active ${service}`);
        serviceStatus[service] = {
          status: 'active',
          controllable: true
        };
      } catch (error) {
        serviceStatus[service] = {
          status: 'inactive',
          controllable: false
        };
      }
    }

    res.json({
      success: true,
      data: {
        timestamp: new Date().toISOString(),
        services: serviceStatus
      }
    });

  } catch (error) {
    logger.error('Service status check failed:', error);
    res.status(500).json({
      error: 'Failed to get service status',
      message: error.message
    });
  }
});

module.exports = router;
