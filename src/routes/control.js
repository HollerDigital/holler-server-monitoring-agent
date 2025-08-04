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
 * Restart Nginx web server
 */
router.post('/restart/nginx', async (req, res) => {
  try {
    logger.logSystemEvent('NGINX_RESTART_REQUESTED', { ip: req.ip, user: req.user?.id });

    // Check if GridPane CLI is available
    await execAsync('which gp');
    
    // Restart nginx using GridPane CLI
    const { stdout, stderr } = await execAsync('gp ngx -restart');
    
    // GridPane CLI handles verification internally

    logger.logSystemEvent('NGINX_RESTART_SUCCESS', { ip: req.ip, user: req.user?.id });

    res.json({
      success: true,
      message: 'Nginx restarted successfully using GridPane CLI',
      output: stdout,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Nginx restart failed:', error);
    logger.logSystemEvent('NGINX_RESTART_FAILED', { 
      error: error.message, 
      ip: req.ip, 
      user: req.user?.id 
    });

    res.status(500).json({
      error: 'Failed to restart Nginx',
      message: error.message
    });
  }
});

/**
 * POST /api/control/restart/mysql
 * Restart MySQL database server
 */
router.post('/restart/mysql', async (req, res) => {
  try {
    logger.logSystemEvent('MYSQL_RESTART_REQUESTED', { ip: req.ip, user: req.user?.id });

    // Check if GridPane CLI is available
    await execAsync('which gp');
    
    // Restart MySQL using GridPane CLI
    const { stdout, stderr } = await execAsync('gp mysql -restart');
    
    // GridPane CLI handles verification internally

    logger.logSystemEvent('MYSQL_RESTART_SUCCESS', { 
      method: 'gridpane-cli',
      ip: req.ip, 
      user: req.user?.id 
    });

    res.json({
      success: true,
      message: 'MySQL restarted successfully using GridPane CLI',
      output: stdout,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('MySQL restart failed:', error);
    logger.logSystemEvent('MYSQL_RESTART_FAILED', { 
      error: error.message, 
      ip: req.ip, 
      user: req.user?.id 
    });

    res.status(500).json({
      error: 'Failed to restart MySQL',
      message: error.message
    });
  }
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
 * Clear all sites cache using GridPane CLI
 */
router.post('/cache/clear', async (req, res) => {
  try {
    logger.logSystemEvent('CACHE_CLEAR_REQUESTED', { ip: req.ip, user: req.user?.id });

    // Check if GridPane CLI is available
    await execAsync('which gp');

    // Clear cache using GridPane CLI
    const { stdout, stderr } = await execAsync('gp fix cached');

    logger.logSystemEvent('CACHE_CLEAR_SUCCESS', { 
      output: stdout,
      ip: req.ip, 
      user: req.user?.id 
    });

    res.json({
      success: true,
      message: 'Cache cleared successfully',
      output: stdout,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Cache clear failed:', error);
    logger.logSystemEvent('CACHE_CLEAR_FAILED', { 
      error: error.message, 
      ip: req.ip, 
      user: req.user?.id 
    });

    // If GridPane CLI is not available, try alternative methods
    if (error.message.includes('which gp')) {
      try {
        // Alternative: Clear common cache locations
        await execAsync('find /var/cache -type f -name "*.cache" -delete 2>/dev/null || true');
        await execAsync('sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true');

        res.json({
          success: true,
          message: 'Cache cleared using alternative method (GridPane CLI not available)',
          timestamp: new Date().toISOString()
        });
        return;
      } catch (altError) {
        // Fall through to error response
      }
    }

    res.status(500).json({
      error: 'Failed to clear cache',
      message: error.message
    });
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
