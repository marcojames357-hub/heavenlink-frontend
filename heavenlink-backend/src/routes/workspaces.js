const express = require('express');
const { body, validationResult } = require('express-validator');
const { authenticateToken, requireRole, requireVerifiedPhone } = require('../middleware/auth');
const { AgentWorkspace, User, AdminAuditEvent } = require('../models');
const workspaces = require('../services/workspaces');

const router = express.Router();

const describe = (records) => records.map((record) => ({
  workspace: record.workspace, status: record.status, source: record.source
}));

router.get('/', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT'), async (req, res, next) => {
  try {
    res.json({ workspaces: describe(await workspaces.ensureAgentWorkspaces(req.user)) });
  } catch (error) { next(error); }
});

// Adds a business category or confirms a legacy account that needs review.
router.post('/', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT'), requireVerifiedPhone, [
  body('workspace').isIn(workspaces.WORKSPACES)
], async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    const existing = await workspaces.ensureAgentWorkspaces(req.user);
    const current = existing.find((record) => record.workspace === req.body.workspace);
    if (current?.status === 'revoked') {
      return res.status(403).json({ error: 'This workspace was revoked. Contact Haven Link support.' });
    }
    await workspaces.grantWorkspace(
      req.user, req.body.workspace, current ? current.source : 'selfSelected'
    );
    res.status(201).json({ workspaces: describe(await AgentWorkspace.findAll({ where: { userId: req.user.id } })) });
  } catch (error) { next(error); }
});

router.get('/admin/:userId', authenticateToken, requireRole('ADMIN'), async (req, res, next) => {
  try {
    const agent = await User.findByPk(req.params.userId);
    if (!agent || !['RENTAL_AGENT', 'STAY_AGENT'].includes(agent.role)) {
      return res.status(404).json({ error: 'Agent not found' });
    }
    res.json({ workspaces: describe(await workspaces.ensureAgentWorkspaces(agent)) });
  } catch (error) { next(error); }
});

router.patch('/admin/:userId/:workspace', authenticateToken, requireRole('ADMIN'), [
  body('status').isIn(['active', 'revoked', 'pending_review']),
  body('reason').optional().isString().trim().isLength({ max: 500 })
], async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    if (!workspaces.WORKSPACES.includes(req.params.workspace)) {
      return res.status(400).json({ error: 'Unknown workspace' });
    }
    const agent = await User.findByPk(req.params.userId);
    if (!agent || !['RENTAL_AGENT', 'STAY_AGENT'].includes(agent.role)) {
      return res.status(404).json({ error: 'Agent not found' });
    }
    await workspaces.ensureAgentWorkspaces(agent);
    const [record] = await AgentWorkspace.findOrCreate({
      where: { userId: agent.id, workspace: req.params.workspace },
      defaults: { status: req.body.status, source: 'admin' }
    });
    await record.update({ status: req.body.status });
    if (req.body.status === 'active') {
      await workspaces.grantWorkspace(agent, req.params.workspace, record.source);
    }
    await AdminAuditEvent.create({
      actorId: req.user.id, action: 'AGENT_WORKSPACE_CHANGED', entityType: 'AgentWorkspace',
      entityId: String(record.id),
      metadata: { agentId: agent.id, workspace: record.workspace, status: record.status, reason: req.body.reason || null }
    });
    res.json({ workspace: describe([record])[0] });
  } catch (error) { next(error); }
});

module.exports = router;
