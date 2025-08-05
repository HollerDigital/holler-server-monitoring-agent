const express = require('express');
const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const logger = require('../utils/logger');

const router = express.Router();

// Environment file path
const ENV_FILE_PATH = '/etc/gridpane-manager/.env';

/**
 * Update API key endpoint
 * Allows secure updating of the API key without service restart
 * Requires either current API key or setup token for authentication
 */
router.post('/update', async (req, res) => {
  const requestId = crypto.randomUUID();
  const startTime = Date.now();
  
  try {
    logger.info(`[${requestId}] API key update requested`, {
      ip: req.ip,
      userAgent: req.get('User-Agent')
    });

    const { newApiKey, setupToken } = req.body;
    const currentApiKey = req.headers['x-api-key'];
    const providedSetupToken = req.headers['x-setup-token'];

    // Validate input
    if (!newApiKey || typeof newApiKey !== 'string' || newApiKey.length < 32) {
      logger.warn(`[${requestId}] Invalid API key format provided`);
      return res.status(400).json({
        success: false,
        error: 'Invalid API key format. Must be at least 32 characters.',
        requestId
      });
    }

    // Read current environment file
    let envContent;
    try {
      envContent = await fs.readFile(ENV_FILE_PATH, 'utf8');
    } catch (error) {
      logger.error(`[${requestId}] Failed to read environment file`, { error: error.message });
      return res.status(500).json({
        success: false,
        error: 'Failed to access configuration',
        requestId
      });
    }

    // Check authentication - either valid current API key or setup token
    const envLines = envContent.split('\n');
    const currentApiKeyLine = envLines.find(line => line.startsWith('API_KEY='));
    const setupTokenLine = envLines.find(line => line.startsWith('SETUP_TOKEN='));
    
    const storedApiKey = currentApiKeyLine ? currentApiKeyLine.split('=')[1] : null;
    const storedSetupToken = setupTokenLine ? setupTokenLine.split('=')[1] : null;

    const isValidApiKey = storedApiKey && currentApiKey === storedApiKey;
    const isValidSetupToken = storedSetupToken && (providedSetupToken === storedSetupToken || setupToken === storedSetupToken);

    if (!isValidApiKey && !isValidSetupToken) {
      logger.warn(`[${requestId}] Unauthorized API key update attempt`, {
        hasCurrentKey: !!currentApiKey,
        hasSetupToken: !!providedSetupToken || !!setupToken,
        ip: req.ip
      });
      return res.status(401).json({
        success: false,
        error: 'Unauthorized. Valid API key or setup token required.',
        requestId
      });
    }

    // Update the API key in environment file
    const updatedEnvLines = envLines.map(line => {
      if (line.startsWith('API_KEY=')) {
        return `API_KEY=${newApiKey}`;
      }
      // Remove setup token after successful key update
      if (line.startsWith('SETUP_TOKEN=')) {
        return '# SETUP_TOKEN removed after API key update';
      }
      return line;
    });

    // If no API_KEY line exists, add it
    if (!currentApiKeyLine) {
      updatedEnvLines.push(`API_KEY=${newApiKey}`);
    }

    const updatedEnvContent = updatedEnvLines.join('\n');

    // Write updated environment file
    try {
      await fs.writeFile(ENV_FILE_PATH, updatedEnvContent, 'utf8');
      logger.info(`[${requestId}] API key updated successfully`);
    } catch (error) {
      logger.error(`[${requestId}] Failed to write environment file`, { error: error.message });
      return res.status(500).json({
        success: false,
        error: 'Failed to update configuration',
        requestId
      });
    }

    // Update runtime environment variable
    process.env.API_KEY = newApiKey;

    const duration = Date.now() - startTime;
    logger.logSystemEvent('API_KEY_UPDATED', {
      requestId,
      duration: `${duration}ms`,
      ip: req.ip,
      authMethod: isValidApiKey ? 'current_key' : 'setup_token'
    });

    res.json({
      success: true,
      message: 'API key updated successfully',
      requestId,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    const duration = Date.now() - startTime;
    logger.error(`[${requestId}] API key update failed`, {
      error: error.message,
      stack: error.stack,
      duration: `${duration}ms`
    });

    res.status(500).json({
      success: false,
      error: 'Internal server error',
      requestId
    });
  }
});

/**
 * Generate setup token endpoint
 * Creates a temporary token for initial API key setup
 * Only works if no API key is currently set
 */
router.post('/setup-token', async (req, res) => {
  const requestId = crypto.randomUUID();
  
  try {
    logger.info(`[${requestId}] Setup token generation requested`, {
      ip: req.ip
    });

    // Read current environment file
    let envContent;
    try {
      envContent = await fs.readFile(ENV_FILE_PATH, 'utf8');
    } catch (error) {
      logger.error(`[${requestId}] Failed to read environment file`, { error: error.message });
      return res.status(500).json({
        success: false,
        error: 'Failed to access configuration',
        requestId
      });
    }

    // Check if API key is already set
    const envLines = envContent.split('\n');
    const currentApiKeyLine = envLines.find(line => line.startsWith('API_KEY='));
    
    if (currentApiKeyLine && currentApiKeyLine.split('=')[1]) {
      logger.warn(`[${requestId}] Setup token requested but API key already exists`);
      return res.status(400).json({
        success: false,
        error: 'API key already configured. Use existing key to update.',
        requestId
      });
    }

    // Generate setup token
    const setupToken = crypto.randomBytes(32).toString('hex');
    
    // Update environment file with setup token
    const updatedEnvLines = envLines.filter(line => !line.startsWith('SETUP_TOKEN='));
    updatedEnvLines.push(`SETUP_TOKEN=${setupToken}`);
    
    const updatedEnvContent = updatedEnvLines.join('\n');

    try {
      await fs.writeFile(ENV_FILE_PATH, updatedEnvContent, 'utf8');
      logger.info(`[${requestId}] Setup token generated successfully`);
    } catch (error) {
      logger.error(`[${requestId}] Failed to write setup token`, { error: error.message });
      return res.status(500).json({
        success: false,
        error: 'Failed to generate setup token',
        requestId
      });
    }

    res.json({
      success: true,
      setupToken,
      message: 'Setup token generated. Use this token to set your API key.',
      expiresIn: '1 hour',
      requestId
    });

  } catch (error) {
    logger.error(`[${requestId}] Setup token generation failed`, {
      error: error.message,
      stack: error.stack
    });

    res.status(500).json({
      success: false,
      error: 'Internal server error',
      requestId
    });
  }
});

/**
 * Get API key status endpoint
 * Returns whether an API key is configured (without revealing the key)
 */
router.get('/status', async (req, res) => {
  const requestId = crypto.randomUUID();
  
  try {
    // Read current environment file
    let envContent;
    try {
      envContent = await fs.readFile(ENV_FILE_PATH, 'utf8');
    } catch (error) {
      return res.status(500).json({
        success: false,
        error: 'Failed to access configuration',
        requestId
      });
    }

    const envLines = envContent.split('\n');
    const currentApiKeyLine = envLines.find(line => line.startsWith('API_KEY='));
    const setupTokenLine = envLines.find(line => line.startsWith('SETUP_TOKEN='));
    
    const hasApiKey = !!(currentApiKeyLine && currentApiKeyLine.split('=')[1]);
    const hasSetupToken = !!(setupTokenLine && setupTokenLine.split('=')[1]);

    res.json({
      success: true,
      hasApiKey,
      hasSetupToken,
      needsSetup: !hasApiKey,
      requestId
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      requestId
    });
  }
});

module.exports = router;
