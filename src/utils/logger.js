/**
 * Winston Logger Configuration
 * Centralized logging for the GridPane Manager Backend
 */

const winston = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');
const path = require('path');

// Use system log directory (created during installation)
const logDir = process.env.LOG_DIR || '/var/log/gridpane-manager';

// Define log format
const logFormat = winston.format.combine(
  winston.format.timestamp({
    format: 'YYYY-MM-DD HH:mm:ss'
  }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ level, message, timestamp, stack }) => {
    if (stack) {
      return `${timestamp} [${level.toUpperCase()}]: ${message}\n${stack}`;
    }
    return `${timestamp} [${level.toUpperCase()}]: ${message}`;
  })
);

// Configure transports
const transports = [
  // Console transport for development
  new winston.transports.Console({
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    format: winston.format.combine(
      winston.format.colorize(),
      logFormat
    )
  }),

  // File transport for all logs
  new DailyRotateFile({
    filename: path.join(logDir, 'gridpane-manager-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: process.env.LOG_MAX_SIZE || '20m',
    maxFiles: process.env.LOG_MAX_FILES || '14d',
    level: process.env.LOG_LEVEL || 'info',
    format: logFormat
  }),

  // Separate file for errors
  new DailyRotateFile({
    filename: path.join(logDir, 'error-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: process.env.LOG_MAX_SIZE || '20m',
    maxFiles: process.env.LOG_MAX_FILES || '14d',
    level: 'error',
    format: logFormat
  })
];

// Create logger instance
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: logFormat,
  transports,
  exitOnError: false
});

// Add request logging helper
logger.logRequest = (req, res, responseTime) => {
  const { method, url, ip } = req;
  const { statusCode } = res;
  const contentLength = res.get('Content-Length') || 0;
  
  logger.info(`${method} ${url} ${statusCode} ${contentLength} - ${responseTime}ms - ${ip}`);
};

// Add system event logging
logger.logSystemEvent = (event, details = {}) => {
  logger.info(`SYSTEM_EVENT: ${event}`, details);
};

// Add security event logging
logger.logSecurityEvent = (event, details = {}) => {
  logger.warn(`SECURITY_EVENT: ${event}`, details);
};

module.exports = logger;
