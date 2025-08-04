/**
 * Monitoring Routes
 * System monitoring endpoints for CPU, memory, disk usage
 * Compatible with existing Python Flask API endpoints
 */

const express = require('express');
const si = require('systeminformation');
const { body, validationResult } = require('express-validator');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * GET /api/monitoring/status
 * Get overall system status and health
 * Compatible with legacy /api/system/metrics endpoint
 */
router.get('/status', async (req, res) => {
  try {
    const [cpu, mem, disk, load, uptime] = await Promise.all([
      si.currentLoad(),
      si.mem(),
      si.fsSize(),
      si.currentLoad(),
      si.time()
    ]);

    const status = {
      timestamp: new Date().toISOString(),
      cpu: {
        usage: Math.round(cpu.currentLoad * 100) / 100,
        cores: cpu.cpus?.length || 0,
        speed: cpu.avgLoad || 0
      },
      memory: {
        total: mem.total,
        used: mem.used,
        free: mem.free,
        usage: Math.round((mem.used / mem.total) * 100 * 100) / 100
      },
      disk: disk.map(d => ({
        filesystem: d.fs,
        size: d.size,
        used: d.used,
        available: d.available,
        usage: Math.round(d.use * 100) / 100,
        mount: d.mount
      })),
      load: {
        avg1: load.avgLoad,
        avg5: load.avgLoad,
        avg15: load.avgLoad
      },
      uptime: uptime.uptime
    };

    res.json({
      success: true,
      data: status
    });

  } catch (error) {
    logger.error('System status error:', error);
    res.status(500).json({
      error: 'Failed to get system status',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/cpu
 * Get detailed CPU information and usage
 */
router.get('/cpu', async (req, res) => {
  try {
    const [cpu, cpuTemp] = await Promise.all([
      si.currentLoad(),
      si.cpuTemperature().catch(() => ({ main: null })) // Temperature might not be available
    ]);

    const cpuData = {
      timestamp: new Date().toISOString(),
      usage: Math.round(cpu.currentLoad * 100) / 100,
      cores: cpu.cpus?.map((core, index) => ({
        core: index,
        usage: Math.round(core.load * 100) / 100
      })) || [],
      temperature: cpuTemp.main,
      speed: cpu.avgLoad || 0
    };

    res.json({
      success: true,
      data: cpuData
    });

  } catch (error) {
    logger.error('CPU monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get CPU data',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/memory
 * Get detailed memory usage information
 */
router.get('/memory', async (req, res) => {
  try {
    const mem = await si.mem();

    const memoryData = {
      timestamp: new Date().toISOString(),
      total: mem.total,
      used: mem.used,
      free: mem.free,
      available: mem.available,
      usage: Math.round((mem.used / mem.total) * 100 * 100) / 100,
      swap: {
        total: mem.swaptotal,
        used: mem.swapused,
        free: mem.swapfree
      }
    };

    res.json({
      success: true,
      data: memoryData
    });

  } catch (error) {
    logger.error('Memory monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get memory data',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/disk
 * Get disk usage information for all mounted filesystems
 */
router.get('/disk', async (req, res) => {
  try {
    const disk = await si.fsSize();

    const diskData = {
      timestamp: new Date().toISOString(),
      filesystems: disk.map(d => ({
        filesystem: d.fs,
        type: d.type,
        size: d.size,
        used: d.used,
        available: d.available,
        usage: Math.round(d.use * 100) / 100,
        mount: d.mount
      }))
    };

    res.json({
      success: true,
      data: diskData
    });

  } catch (error) {
    logger.error('Disk monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get disk data',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/services
 * Get status of important services (nginx, mysql, etc.)
 * Compatible with legacy /api/services/status endpoint
 */
router.get('/services', async (req, res) => {
  try {
    const { exec } = require('child_process');
    const { promisify } = require('util');
    const execAsync = promisify(exec);

    const services = ['nginx', 'mysql', 'apache2', 'php8.1-fpm', 'redis-server', 'fail2ban', 'ssh'];
    const serviceStatus = {};

    for (const service of services) {
      try {
        await execAsync(`systemctl is-active ${service}`);
        serviceStatus[service] = 'active';
      } catch (error) {
        serviceStatus[service] = 'inactive';
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
    logger.error('Service monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get service status',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/processes
 * Get running processes information
 * Compatible with legacy /api/processes/top endpoint
 */
router.get('/processes', async (req, res) => {
  try {
    const processes = await si.processes();

    const processData = {
      timestamp: new Date().toISOString(),
      total: processes.all,
      running: processes.running,
      blocked: processes.blocked,
      sleeping: processes.sleeping,
      top: processes.list.slice(0, 10).map(proc => ({
        pid: proc.pid,
        name: proc.name,
        cpu: proc.cpu,
        memory: proc.mem,
        command: proc.command
      }))
    };

    res.json({
      success: true,
      data: processData
    });

  } catch (error) {
    logger.error('Process monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get process data',
      message: error.message
    });
  }
});

/**
 * GET /api/monitoring/network
 * Get network interface statistics
 */
router.get('/network', async (req, res) => {
  try {
    const [interfaces, stats] = await Promise.all([
      si.networkInterfaces(),
      si.networkStats()
    ]);

    const networkData = {
      timestamp: new Date().toISOString(),
      interfaces: interfaces.map(iface => ({
        name: iface.iface,
        ip4: iface.ip4,
        ip6: iface.ip6,
        mac: iface.mac,
        internal: iface.internal,
        virtual: iface.virtual,
        speed: iface.speed
      })),
      stats: stats.map(stat => ({
        interface: stat.iface,
        bytesReceived: stat.rx_bytes,
        bytesSent: stat.tx_bytes,
        packetsReceived: stat.rx_sec,
        packetsSent: stat.tx_sec
      }))
    };

    res.json({
      success: true,
      data: networkData
    });

  } catch (error) {
    logger.error('Network monitoring error:', error);
    res.status(500).json({
      error: 'Failed to get network data',
      message: error.message
    });
  }
});

// Legacy compatibility endpoints
router.get('/system/metrics', (req, res) => {
  // Redirect to new status endpoint
  req.url = '/status';
  router.handle(req, res);
});

router.get('/services/status', (req, res) => {
  // Redirect to new services endpoint
  req.url = '/services';
  router.handle(req, res);
});

router.get('/processes/top', (req, res) => {
  // Redirect to new processes endpoint
  req.url = '/processes';
  router.handle(req, res);
});

module.exports = router;
