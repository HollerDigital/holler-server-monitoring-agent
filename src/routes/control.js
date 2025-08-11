/**
 * Control Routes
 * Server control endpoints for service restarts, cache clearing, etc.
 * Enhanced for minimal server agent architecture
 */

const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const { body, validationResult } = require('express-validator');
const logger = require('../utils/logger');
const systemctl = require('../services/systemctl');
const agentConfig = require('../config/agent');

const router = express.Router();
const execAsync = promisify(exec);

/**
 * POST /api/control/restart/nginx
 * Restart Nginx service
 */
router.post('/restart/nginx', async (req, res) => {
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.restartService('nginx', {
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      message: 'Nginx restarted successfully',
      service: 'nginx',
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Nginx restart failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to restart Nginx',
      message: error.message,
      service: 'nginx',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/control/restart/mysql
 * Restart MySQL/MariaDB database server
 */
router.post('/restart/mysql', async (req, res) => {
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.restartService('database', {
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      message: 'Database service restarted successfully',
      service: 'database',
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Database restart failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to restart database service',
      message: error.message,
      service: 'database',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/control/restart/php-fpm
 * Restart PHP-FPM service (auto-detects version)
 */
router.post('/restart/php-fpm', async (req, res) => {
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.restartService('php-fpm', {
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      message: 'PHP-FPM restarted successfully',
      service: 'php-fpm',
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] PHP-FPM restart failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to restart PHP-FPM',
      message: error.message,
      service: 'php-fpm',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/control/restart/redis
 * Restart Redis server
 */
router.post('/restart/redis', async (req, res) => {
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.restartService('redis-server', {
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      message: 'Redis server restarted successfully',
      service: 'redis-server',
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Redis restart failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to restart Redis server',
      message: error.message,
      service: 'redis-server',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/control/restart/supervisor
 * Restart Supervisor (queue workers)
 */
router.post('/restart/supervisor', async (req, res) => {
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.restartService('supervisor', {
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      message: 'Supervisor (queue workers) restarted successfully',
      service: 'supervisor',
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Supervisor restart failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to restart Supervisor',
      message: error.message,
      service: 'supervisor',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/control/service/:action/:service
 * Generic service control endpoint
 */
router.post('/service/:action/:service', async (req, res) => {
  const { action, service } = req.params;
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    // Validate action
    const allowedActions = ['start', 'stop', 'restart', 'reload'];
    if (!allowedActions.includes(action)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid action',
        message: `Action must be one of: ${allowedActions.join(', ')}`,
        requestId
      });
    }

    let result;
    switch (action) {
      case 'start':
        result = await systemctl.startService(service, { requestId, ip: req.ip, user: req.user?.id });
        break;
      case 'stop':
        result = await systemctl.stopService(service, { requestId, ip: req.ip, user: req.user?.id });
        break;
      case 'restart':
        result = await systemctl.restartService(service, { requestId, ip: req.ip, user: req.user?.id });
        break;
      case 'reload':
        result = await systemctl.reloadService(service, { requestId, ip: req.ip, user: req.user?.id });
        break;
    }

    res.json({
      success: true,
      message: `Service ${service} ${action} completed successfully`,
      action,
      service,
      ...result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Service ${action} failed for ${service}:`, error);
    res.status(500).json({
      success: false,
      error: `Failed to ${action} service ${service}`,
      message: error.message,
      action,
      service,
      requestId,
      timestamp: new Date().toISOString()
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
    logger.info(`[${requestId}] GridPane CLI found at /usr/local/bin/gp`);
    
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
  const requestId = Math.random().toString(36).substr(2, 9);
  
  try {
    const result = await systemctl.getAllServicesStatus({
      requestId,
      ip: req.ip,
      user: req.user?.id
    });

    res.json({
      success: true,
      data: result,
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Service status check failed:`, error);
    res.status(500).json({
      success: false,
      error: 'Failed to get service status',
      message: error.message,
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
