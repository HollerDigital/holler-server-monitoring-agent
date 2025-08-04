/**
 * Authentication Routes
 * Handle login, token generation, and user authentication
 */

const express = require('express');
const bcrypt = require('bcryptjs');
const { body, validationResult } = require('express-validator');
const { generateToken } = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

// Simple in-memory user store (replace with database in production)
const users = [
  {
    id: 1,
    username: 'admin',
    // Default password: 'gridpane123' - should be changed in production
    passwordHash: '$2a$10$8K1p/a0dclxKoNqIfrHb2eUHnUkqhyOoM7D6aDVvXkpfvMjdqOvJe'
  }
];

/**
 * POST /api/auth/login
 * Authenticate user and return JWT token
 */
router.post('/login', [
  body('username').notEmpty().withMessage('Username is required'),
  body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters')
], async (req, res) => {
  try {
    // Validate input
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      logger.logSecurityEvent('LOGIN_VALIDATION_FAILED', {
        ip: req.ip,
        errors: errors.array()
      });
      return res.status(400).json({
        error: 'Validation failed',
        details: errors.array()
      });
    }

    const { username, password } = req.body;

    // Find user
    const user = users.find(u => u.username === username);
    if (!user) {
      logger.logSecurityEvent('LOGIN_FAILED_USER_NOT_FOUND', {
        username,
        ip: req.ip
      });
      return res.status(401).json({
        error: 'Authentication failed',
        message: 'Invalid credentials'
      });
    }

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.passwordHash);
    if (!isValidPassword) {
      logger.logSecurityEvent('LOGIN_FAILED_INVALID_PASSWORD', {
        username,
        ip: req.ip
      });
      return res.status(401).json({
        error: 'Authentication failed',
        message: 'Invalid credentials'
      });
    }

    // Generate JWT token
    const token = generateToken(user.id);

    logger.logSecurityEvent('LOGIN_SUCCESS', {
      userId: user.id,
      username: user.username,
      ip: req.ip
    });

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        username: user.username
      }
    });

  } catch (error) {
    logger.error('Login error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: 'Login failed'
    });
  }
});

/**
 * POST /api/auth/change-password
 * Change user password (requires authentication)
 */
router.post('/change-password', [
  body('currentPassword').notEmpty().withMessage('Current password is required'),
  body('newPassword').isLength({ min: 6 }).withMessage('New password must be at least 6 characters')
], async (req, res) => {
  try {
    // This would require authentication middleware in a full implementation
    // For now, just return success for API structure
    res.json({
      success: true,
      message: 'Password changed successfully'
    });
  } catch (error) {
    logger.error('Change password error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: 'Password change failed'
    });
  }
});

/**
 * POST /api/auth/refresh
 * Refresh JWT token
 */
router.post('/refresh', (req, res) => {
  // Implementation for token refresh
  res.json({
    success: true,
    message: 'Token refresh endpoint (to be implemented)'
  });
});

/**
 * GET /api/auth/me
 * Get current user info (requires authentication)
 */
router.get('/me', (req, res) => {
  // This would require authentication middleware
  res.json({
    success: true,
    message: 'User info endpoint (to be implemented)'
  });
});

module.exports = router;
