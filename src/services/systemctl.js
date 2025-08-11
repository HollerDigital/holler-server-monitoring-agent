/**
 * SystemD Service Control Module
 * Secure wrapper for systemctl operations with proper logging and validation
 */

const { exec } = require('child_process');
const { promisify } = require('util');
const logger = require('../utils/logger');
const agentConfig = require('../config/agent');

const execAsync = promisify(exec);

class SystemCtlService {
  constructor() {
    this.allowedServices = agentConfig.services.controllable;
    this.serviceAliases = agentConfig.services.aliases;
  }

  /**
   * Validate if service is allowed to be controlled
   */
  isServiceAllowed(serviceName) {
    // Check direct service name
    if (this.allowedServices.includes(serviceName)) {
      return true;
    }

    // Check aliases
    for (const [alias, services] of Object.entries(this.serviceAliases)) {
      if (alias === serviceName && services.some(s => this.allowedServices.includes(s))) {
        return true;
      }
    }

    return false;
  }

  /**
   * Resolve service alias to actual service names
   */
  resolveServiceName(serviceName) {
    if (this.serviceAliases[serviceName]) {
      // Return first available service from alias
      for (const service of this.serviceAliases[serviceName]) {
        if (this.allowedServices.includes(service)) {
          return service;
        }
      }
    }
    return serviceName;
  }

  /**
   * Execute systemctl command with proper validation and logging
   */
  async executeSystemCtl(action, serviceName, options = {}) {
    const requestId = options.requestId || Math.random().toString(36).substr(2, 9);
    const startTime = Date.now();

    try {
      // Validate service
      if (!this.isServiceAllowed(serviceName)) {
        throw new Error(`Service '${serviceName}' is not allowed to be controlled`);
      }

      // Resolve service name
      const resolvedService = this.resolveServiceName(serviceName);

      // Validate action
      const allowedActions = ['start', 'stop', 'restart', 'reload', 'status', 'is-active', 'is-enabled'];
      if (!allowedActions.includes(action)) {
        throw new Error(`Action '${action}' is not allowed`);
      }

      // Build command
      const command = `sudo systemctl ${action} ${resolvedService}`;
      
      logger.info(`[${requestId}] Executing systemctl command`, {
        action,
        service: serviceName,
        resolvedService,
        command: command.replace('sudo ', ''), // Don't log sudo for security
        ip: options.ip,
        user: options.user
      });

      // Execute command
      const { stdout, stderr } = await execAsync(command, {
        timeout: options.timeout || 30000 // 30 second timeout
      });

      const duration = Date.now() - startTime;

      // Log success
      logger.info(`[${requestId}] SystemCtl command completed successfully`, {
        action,
        service: serviceName,
        resolvedService,
        duration: `${duration}ms`,
        stdoutLength: stdout.length,
        stderrLength: stderr.length
      });

      // Log audit event
      logger.logSystemEvent('SYSTEMCTL_SUCCESS', {
        requestId,
        action,
        service: serviceName,
        resolvedService,
        duration: `${duration}ms`,
        ip: options.ip,
        user: options.user
      });

      return {
        success: true,
        action,
        service: serviceName,
        resolvedService,
        output: stdout.trim(),
        warnings: stderr.trim() || null,
        duration: `${duration}ms`,
        timestamp: new Date().toISOString()
      };

    } catch (error) {
      const duration = Date.now() - startTime;

      logger.error(`[${requestId}] SystemCtl command failed`, {
        action,
        service: serviceName,
        error: error.message,
        duration: `${duration}ms`,
        ip: options.ip,
        user: options.user
      });

      // Log audit event
      logger.logSystemEvent('SYSTEMCTL_FAILED', {
        requestId,
        action,
        service: serviceName,
        error: error.message,
        duration: `${duration}ms`,
        ip: options.ip,
        user: options.user
      });

      throw error;
    }
  }

  /**
   * Get service status
   */
  async getServiceStatus(serviceName, options = {}) {
    try {
      const result = await this.executeSystemCtl('status', serviceName, options);
      
      // Parse status output
      const output = result.output;
      const isActive = output.includes('Active: active');
      const isEnabled = output.includes('Loaded:') && output.includes('enabled');
      
      return {
        ...result,
        parsed: {
          active: isActive,
          enabled: isEnabled,
          status: isActive ? 'active' : 'inactive'
        }
      };
    } catch (error) {
      // Service might not exist or be inactive
      return {
        success: false,
        service: serviceName,
        error: error.message,
        parsed: {
          active: false,
          enabled: false,
          status: 'not-found'
        }
      };
    }
  }

  /**
   * Check if service is active
   */
  async isServiceActive(serviceName, options = {}) {
    try {
      await this.executeSystemCtl('is-active', serviceName, options);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Start service
   */
  async startService(serviceName, options = {}) {
    return await this.executeSystemCtl('start', serviceName, options);
  }

  /**
   * Stop service
   */
  async stopService(serviceName, options = {}) {
    return await this.executeSystemCtl('stop', serviceName, options);
  }

  /**
   * Restart service
   */
  async restartService(serviceName, options = {}) {
    return await this.executeSystemCtl('restart', serviceName, options);
  }

  /**
   * Reload service configuration
   */
  async reloadService(serviceName, options = {}) {
    return await this.executeSystemCtl('reload', serviceName, options);
  }

  /**
   * Get status of all controllable services
   */
  async getAllServicesStatus(options = {}) {
    const requestId = options.requestId || Math.random().toString(36).substr(2, 9);
    const results = {};

    logger.info(`[${requestId}] Getting status for all controllable services`);

    for (const service of this.allowedServices) {
      try {
        const status = await this.getServiceStatus(service, { 
          ...options, 
          requestId: `${requestId}-${service}` 
        });
        results[service] = status.parsed;
      } catch (error) {
        results[service] = {
          active: false,
          enabled: false,
          status: 'error',
          error: error.message
        };
      }
    }

    // Add alias information
    const aliasInfo = {};
    for (const [alias, services] of Object.entries(this.serviceAliases)) {
      const activeServices = services.filter(s => results[s]?.active);
      aliasInfo[alias] = {
        services,
        activeCount: activeServices.length,
        active: activeServices.length > 0,
        activeServices
      };
    }

    return {
      services: results,
      aliases: aliasInfo,
      timestamp: new Date().toISOString(),
      requestId
    };
  }
}

module.exports = new SystemCtlService();
