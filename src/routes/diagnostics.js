/**
 * Diagnostics Routes
 * System diagnostics and service availability checks
 */

const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const logger = require('../utils/logger');

const router = express.Router();
const execAsync = promisify(exec);

/**
 * GET /api/diagnostics/monit
 * Check if Monit is installed and HTTP API is available
 */
router.get('/monit', async (req, res) => {
  try {
    const diagnostics = {
      timestamp: new Date().toISOString(),
      monit: {
        installed: false,
        running: false,
        httpEnabled: false,
        port: null,
        configFile: null,
        services: [],
        error: null
      }
    };

    // Check if monit is installed
    try {
      const { stdout: monitVersion } = await execAsync('monit -V 2>/dev/null | head -1');
      if (monitVersion.trim()) {
        diagnostics.monit.installed = true;
        logger.info(`Monit version found: ${monitVersion.trim()}`);
      }
    } catch (error) {
      diagnostics.monit.error = 'Monit not installed or not in PATH';
      logger.warn('Monit not found in PATH');
    }

    // Check if monit is running
    if (diagnostics.monit.installed) {
      try {
        const { stdout: monitStatus } = await execAsync('monit status 2>/dev/null');
        if (monitStatus.includes('Monit')) {
          diagnostics.monit.running = true;
          logger.info('Monit daemon is running');
        }
      } catch (error) {
        diagnostics.monit.error = 'Monit daemon not running';
        logger.warn('Monit daemon not running');
      }
    }

    // Check monit configuration for HTTP interface
    if (diagnostics.monit.running) {
      try {
        // Try to find monit config file
        const configPaths = [
          '/etc/monit/monitrc',
          '/etc/monitrc',
          '/usr/local/etc/monitrc',
          '/opt/monit/monitrc'
        ];

        for (const configPath of configPaths) {
          try {
            const { stdout: configContent } = await execAsync(`cat ${configPath} 2>/dev/null`);
            if (configContent) {
              diagnostics.monit.configFile = configPath;
              
              // Look for HTTP interface configuration
              const httpMatch = configContent.match(/set\s+httpd\s+port\s+(\d+)/i);
              if (httpMatch) {
                diagnostics.monit.port = parseInt(httpMatch[1]);
                diagnostics.monit.httpEnabled = true;
                logger.info(`Monit HTTP interface found on port ${diagnostics.monit.port}`);
              }
              break;
            }
          } catch (error) {
            // Continue to next config path
          }
        }
      } catch (error) {
        logger.warn('Could not read monit configuration');
      }
    }

    // Test HTTP API accessibility
    if (diagnostics.monit.httpEnabled && diagnostics.monit.port) {
      try {
        // Test common endpoints and authentication methods
        const testEndpoints = [
          `http://localhost:${diagnostics.monit.port}/_status?format=json`,
          `http://127.0.0.1:${diagnostics.monit.port}/_status?format=json`,
          `http://localhost:${diagnostics.monit.port}/_status`,
          `http://127.0.0.1:${diagnostics.monit.port}/_status`
        ];

        for (const endpoint of testEndpoints) {
          try {
            const response = await fetch(endpoint, {
              timeout: 5000,
              headers: {
                'User-Agent': 'GridPane-Manager-Backend'
              }
            });
            
            if (response.ok) {
              const data = await response.text();
              diagnostics.monit.httpAccessible = true;
              diagnostics.monit.testEndpoint = endpoint;
              
              // Try to parse as JSON if possible
              try {
                const jsonData = JSON.parse(data);
                if (jsonData.monit && jsonData.monit.server) {
                  diagnostics.monit.services = jsonData.monit.server.map(service => ({
                    name: service.name,
                    status: service.status,
                    type: service.type
                  }));
                }
              } catch (parseError) {
                // Not JSON, but HTTP API is accessible
                logger.info('Monit HTTP API accessible but not JSON format');
              }
              
              logger.info(`Monit HTTP API accessible at ${endpoint}`);
              break;
            }
          } catch (fetchError) {
            // Continue to next endpoint
          }
        }
      } catch (error) {
        diagnostics.monit.error = `HTTP API test failed: ${error.message}`;
        logger.warn(`Monit HTTP API test failed: ${error.message}`);
      }
    }

    // Additional system checks
    try {
      // Check for common GridPane services that might be monitored
      const { stdout: psOutput } = await execAsync('ps aux | grep -E "(nginx|mysql|php-fpm)" | grep -v grep');
      const runningServices = psOutput.split('\n').filter(line => line.trim());
      diagnostics.systemServices = runningServices.length;
    } catch (error) {
      diagnostics.systemServices = 0;
    }

    res.json(diagnostics);
  } catch (error) {
    logger.error('Diagnostics error:', error);
    res.status(500).json({
      error: 'Diagnostics failed',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /api/diagnostics/system
 * General system diagnostics
 */
router.get('/system', async (req, res) => {
  try {
    const diagnostics = {
      timestamp: new Date().toISOString(),
      os: process.platform,
      nodeVersion: process.version,
      uptime: process.uptime(),
      gridpane: {
        cliAvailable: false,
        version: null
      }
    };

    // Check GridPane CLI
    try {
      const { stdout: gpVersion } = await execAsync('gp --version 2>/dev/null');
      if (gpVersion.trim()) {
        diagnostics.gridpane.cliAvailable = true;
        diagnostics.gridpane.version = gpVersion.trim();
      }
    } catch (error) {
      diagnostics.gridpane.error = 'GridPane CLI not available';
    }

    res.json(diagnostics);
  } catch (error) {
    logger.error('System diagnostics error:', error);
    res.status(500).json({
      error: 'System diagnostics failed',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
