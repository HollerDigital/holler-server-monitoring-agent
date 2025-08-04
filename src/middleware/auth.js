/**
 * Authentication Middleware
 * JWT token validation and API key verification
 */

const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');

/**
 * Middleware to authenticate JWT tokens
 */
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    logger.warn(`Authentication failed: No token provided - ${req.ip}`);
    return res.status(401).json({
      error: 'Access denied',
      message: 'No token provided'
    });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      logger.warn(`Authentication failed: Invalid token - ${req.ip}`);
      return res.status(403).json({
        error: 'Access denied',
        message: 'Invalid or expired token'
      });
    }

    req.user = user;
    logger.debug(`Authentication successful for user: ${user.id}`);
    next();
  });
};

/**
 * Middleware to authenticate API keys (alternative to JWT)
 */
const authenticateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];

  if (!apiKey) {
    logger.warn(`API key authentication failed: No key provided - ${req.ip}`);
    return res.status(401).json({
      error: 'Access denied',
      message: 'No API key provided'
    });
  }

  if (apiKey !== process.env.API_KEY) {
    logger.warn(`API key authentication failed: Invalid key - ${req.ip}`);
    return res.status(403).json({
      error: 'Access denied',
      message: 'Invalid API key'
    });
  }

  logger.debug(`API key authentication successful - ${req.ip}`);
  next();
};

/**
 * Middleware that accepts either JWT token or API key
 */
const authenticateEither = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const apiKey = req.headers['x-api-key'];

  if (authHeader && authHeader.startsWith('Bearer ')) {
    // Try JWT authentication
    return authenticateToken(req, res, next);
  } else if (apiKey) {
    // Try API key authentication
    return authenticateApiKey(req, res, next);
  } else {
    logger.warn(`Authentication failed: No credentials provided - ${req.ip}`);
    return res.status(401).json({
      error: 'Access denied',
      message: 'No authentication credentials provided'
    });
  }
};

/**
 * Generate JWT token for authenticated user
 */
const generateToken = (userId, expiresIn = '24h') => {
  return jwt.sign(
    { 
      id: userId,
      iat: Math.floor(Date.now() / 1000)
    },
    process.env.JWT_SECRET,
    { expiresIn }
  );
};

module.exports = {
  authenticateToken,
  authenticateApiKey,
  authenticateEither,
  generateToken
};
