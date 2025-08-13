/**
 * WordPress Management Routes
 * Handles WordPress-specific operations via GridPane CLI
 */

const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const logger = require('../utils/logger');

const router = express.Router();
const execAsync = promisify(exec);

/**
 * Generate WordPress Magic Login Link
 * Creates a temporary login URL that expires in 15 minutes
 * 
 * POST /api/wordpress/magic-login
 * Body: { siteUrl: "example.com", userId: 1 }
 */
router.post('/magic-login', async (req, res) => {
  const requestId = Date.now().toString();
  const { siteUrl, userId = 1 } = req.body;

  logger.info(`[${requestId}] WordPress magic login requested`, {
    siteUrl,
    userId,
    ip: req.ip
  });

  // Validate required parameters
  if (!siteUrl) {
    logger.warn(`[${requestId}] Missing siteUrl parameter`);
    return res.status(400).json({
      success: false,
      error: 'Site URL is required',
      requestId
    });
  }

  // Sanitize inputs
  const sanitizedSiteUrl = siteUrl.replace(/[^a-zA-Z0-9.-]/g, '');
  const sanitizedUserId = parseInt(userId) || 1;

  try {
    // Execute GridPane WP-CLI magic login command
    const command = `gp wp ${sanitizedSiteUrl} login create ${sanitizedUserId}`;
    
    logger.info(`[${requestId}] Executing command: ${command}`);
    
    const { stdout, stderr } = await execAsync(command, {
      timeout: 30000, // 30 second timeout
      cwd: '/home/gridpane' // GridPane user home directory
    });

    if (stderr && stderr.trim()) {
      logger.warn(`[${requestId}] Command stderr: ${stderr}`);
    }

    // Parse the magic login URL from stdout
    const output = stdout.trim();
    logger.info(`[${requestId}] Command output: ${output}`);

    // Look for URL pattern in output
    const urlMatch = output.match(/(https?:\/\/[^\s]+)/);
    
    if (urlMatch) {
      const magicLoginUrl = urlMatch[1];
      
      logger.info(`[${requestId}] Magic login URL generated successfully`, {
        siteUrl: sanitizedSiteUrl,
        userId: sanitizedUserId,
        urlGenerated: true
      });

      res.json({
        success: true,
        data: {
          magicLoginUrl,
          expiresIn: '15 minutes',
          userId: sanitizedUserId,
          siteUrl: sanitizedSiteUrl
        },
        requestId
      });
    } else {
      // No URL found in output - command may have failed
      logger.error(`[${requestId}] No magic login URL found in output: ${output}`);
      
      res.status(500).json({
        success: false,
        error: 'Failed to generate magic login URL',
        details: output,
        requestId
      });
    }

  } catch (error) {
    logger.error(`[${requestId}] Magic login generation failed`, {
      error: error.message,
      siteUrl: sanitizedSiteUrl,
      userId: sanitizedUserId
    });

    res.status(500).json({
      success: false,
      error: 'Failed to generate magic login URL',
      details: error.message,
      requestId
    });
  }
});

/**
 * List WordPress Users
 * Get list of WordPress users for a site (useful for getting user IDs)
 * 
 * GET /api/wordpress/users?siteUrl=example.com
 */
router.get('/users', async (req, res) => {
  const requestId = Date.now().toString();
  const { siteUrl } = req.query;

  logger.info(`[${requestId}] WordPress users list requested`, {
    siteUrl,
    ip: req.ip
  });

  if (!siteUrl) {
    return res.status(400).json({
      success: false,
      error: 'Site URL is required',
      requestId
    });
  }

  const sanitizedSiteUrl = siteUrl.replace(/[^a-zA-Z0-9.-]/g, '');

  try {
    const command = `gp wp ${sanitizedSiteUrl} user list --format=json`;
    
    logger.info(`[${requestId}] Executing command: ${command}`);
    
    const { stdout, stderr } = await execAsync(command, {
      timeout: 30000,
      cwd: '/home/gridpane'
    });

    if (stderr && stderr.trim()) {
      logger.warn(`[${requestId}] Command stderr: ${stderr}`);
    }

    const output = stdout.trim();
    
    try {
      const users = JSON.parse(output);
      
      logger.info(`[${requestId}] WordPress users retrieved successfully`, {
        siteUrl: sanitizedSiteUrl,
        userCount: users.length
      });

      res.json({
        success: true,
        data: {
          users,
          siteUrl: sanitizedSiteUrl
        },
        requestId
      });
    } catch (parseError) {
      logger.error(`[${requestId}] Failed to parse users JSON: ${parseError.message}`);
      
      res.status(500).json({
        success: false,
        error: 'Failed to parse user data',
        details: output,
        requestId
      });
    }

  } catch (error) {
    logger.error(`[${requestId}] WordPress users list failed`, {
      error: error.message,
      siteUrl: sanitizedSiteUrl
    });

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve WordPress users',
      details: error.message,
      requestId
    });
  }
});

/**
 * Health check endpoint
 */
router.get('/health', (req, res) => {
  res.json({
    success: true,
    service: 'wordpress',
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;
