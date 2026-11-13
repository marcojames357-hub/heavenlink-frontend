const express = require('express');
const { body, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const { User, OtpChallenge } = require('../models');
const { authenticateToken, generateToken } = require('../middleware/auth');
const workspaces = require('../services/workspaces');

const router = express.Router();

// Register
router.post('/register', [
  body('fullName').trim().isLength({ min: 2, max: 100 }),
  body('email').isEmail().normalizeEmail(),
  body('phone').matches(/^\+255\d{9}$/),
  body('role').isIn(['CUSTOMER', 'RENTAL_AGENT', 'STAY_AGENT']),
  body('workspaces').optional().isArray({ min: 1, max: 3 }),
  body('workspaces.*').isIn(workspaces.WORKSPACES),
  body('password').isLength({ min: 8, max: 128 }),
  body('challengeId').isUUID(),
  body('sessionId').isString().trim().isLength({ min: 1, max: 128 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { fullName, email, phone, password, role, challengeId, sessionId } = req.body;

    // Check if user already exists
    const existingUser = await User.findOne({ 
      where: { 
        [Op.or]: [{ email }, { phone }]
      } 
    });

    if (existingUser) {
      return res.status(409).json({ error: 'User with this email or phone already exists' });
    }

    const challenge = await OtpChallenge.findOne({
      where: {
        id: challengeId,
        phoneE164: phone,
        sessionId,
        verified: true,
        consumedAt: null
      }
    });
    if (!challenge || challenge.isExpired()) {
      return res.status(403).json({ error: 'Phone verification is required' });
    }

    const requested = [...new Set(req.body.workspaces || [])];
    if (role === 'CUSTOMER' && requested.length) {
      return res.status(400).json({ error: 'Customers cannot select agent workspaces' });
    }
    if (role === 'RENTAL_AGENT' && requested.some((workspace) => workspace !== 'RENTAL')) {
      return res.status(400).json({ error: 'Rental agents can only select the Long-Term Rentals workspace' });
    }
    const agentRole = role === 'CUSTOMER' ? 'CUSTOMER'
      : requested.length && requested.every((workspace) => workspace === 'RENTAL') ? 'RENTAL_AGENT'
        : requested.length ? 'STAY_AGENT' : role;
    const capabilities = [...new Set(requested.map((workspace) => workspaces.WORKSPACE_CAPABILITY[workspace]))];
    if (!requested.length && agentRole === 'RENTAL_AGENT') capabilities.push('rentalProperty');
    const user = await User.create({
      fullName,
      email,
      phone,
      password,
      role: agentRole,
      capabilities,
      verification: 'verified',
      accountEnabled: true
    });
    if (agentRole !== 'CUSTOMER') {
      if (requested.length) {
        for (const workspace of requested) await workspaces.grantWorkspace(user, workspace, 'registration');
      } else if (agentRole === 'RENTAL_AGENT') {
        await workspaces.grantWorkspace(user, 'RENTAL', 'registration');
      } else {
        // A stays agent must choose Apartments or Hotels before managing properties.
        await workspaces.ensureAgentWorkspaces(user);
      }
    }
    await challenge.update({ consumedAt: new Date() });

    const token = generateToken(user);

    res.status(201).json({
      message: 'Registration successful',
      token,
      user: {
        id: user.id,
        fullName: user.fullName,
        email: user.email,
        phone: user.phone,
        role: user.role,
        verification: user.verification,
        capabilities: user.capabilities,
        workspaces: agentRole === 'CUSTOMER' ? [] : (await workspaces.ensureAgentWorkspaces(user))
          .map((record) => ({ workspace: record.workspace, status: record.status }))
      }
    });
  } catch (error) {
    if (error.name === 'SequelizeUniqueConstraintError') {
      return res.status(409).json({ error: 'Email or phone number is already registered' });
    }
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Login
const workspaceSummary = async (user) =>
  (await workspaces.ensureAgentWorkspaces(user))
    .map((record) => ({ workspace: record.workspace, status: record.status }));

router.post(['/login', '/sign-in'], [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 8, max: 128 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { email, password } = req.body;

    const user = await User.findOne({ where: { email } });
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (!user.password) {
      return res.status(401).json({ error: 'Please use phone verification to sign in' });
    }

    const isPasswordValid = await user.comparePassword(password);
    if (!isPasswordValid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (!user.accountEnabled) {
      return res.status(403).json({ error: 'Account is suspended' });
    }

    const token = generateToken(user);

    res.json({
      message: 'Login successful',
      token,
      user: {
        id: user.id,
        fullName: user.fullName,
        email: user.email,
        phone: user.phone,
        role: user.role,
        verification: user.verification,
        capabilities: user.capabilities,
        workspaces: await workspaceSummary(user)
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Get current user
router.get('/me', authenticateToken, async (req, res) => {
  try {
    res.json({
      user: {
        id: req.user.id,
        fullName: req.user.fullName,
        email: req.user.email,
        phone: req.user.phone,
        role: req.user.role,
        verification: req.user.verification,
        capabilities: req.user.capabilities,
        workspaces: await workspaceSummary(req.user),
        accountEnabled: req.user.accountEnabled
      }
    });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to fetch user data' });
  }
});

// Update profile
router.put('/profile', authenticateToken, [
  body('fullName').optional().trim().isLength({ min: 2, max: 100 }),
  body('email').optional().isEmail().normalizeEmail()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { fullName, email } = req.body;
    const updates = {};

    if (fullName) updates.fullName = fullName;
    if (email) updates.email = email;

    await req.user.update(updates);

    res.json({
      message: 'Profile updated successfully',
      user: {
        id: req.user.id,
        fullName: req.user.fullName,
        email: req.user.email,
        phone: req.user.phone,
        role: req.user.role,
        verification: req.user.verification,
        capabilities: req.user.capabilities
      }
    });
  } catch (error) {
    console.error('Profile update error:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
