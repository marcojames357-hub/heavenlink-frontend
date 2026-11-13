const crypto = require('crypto');
const express = require('express');
const fs = require('fs');
const rateLimit = require('express-rate-limit');
const { body, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const {
  sequelize, Booking, Property, ProblemReport, ProblemReportNote, User, AdminAuditEvent
} = require('../models');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { acceptFiles, storeFiles, removeFiles, filePath } = require('../services/uploads');
const { notify, notifyAdmins } = require('../services/notify');

const router = express.Router();
const sensitiveWords = /\b(fraud|scam|harass\w*|assault\w*|threat\w*|bribe\w*|extort\w*|abuse\w*|stole\w*|steal\w*)\b/i;

const submissionLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  keyGenerator: (req) => req.user?.id || req.ip,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many reports. Please try again later.' }
});

const cleanText = (value, max) => String(value || '')
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
  .replace(/<[^>]*>/g, '')
  .trim()
  .slice(0, max);

const makeReference = () => `HLR-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;

const evidenceUrls = (report) => (report.evidenceFiles || [])
  .map((name) => `/api/v1/reports/${report.id}/evidence/${name}`);

const noteView = (note) => ({
  id: note.id,
  authorRole: note.authorRole,
  visibility: note.visibility,
  kind: note.kind,
  body: note.body,
  createdAt: note.createdAt
});

const baseView = (report) => ({
  id: report.id,
  reference: report.reference,
  bookingId: report.bookingId,
  propertyId: report.propertyId,
  propertyName: report.property?.name,
  category: report.category,
  severity: report.severity,
  description: report.description,
  evidence: evidenceUrls(report),
  status: report.status,
  createdAt: report.createdAt,
  updatedAt: report.updatedAt,
  resolvedAt: report.resolvedAt
});

// Customers never see internal or agent-only notes or routing details.
const customerView = (report) => ({
  ...baseView(report),
  notes: (report.notes || []).filter((note) => note.visibility === 'customer').map(noteView)
});

const agentView = (report) => ({
  ...baseView(report),
  customerName: String(report.customer?.fullName || 'Guest').split(/\s+/)[0],
  notes: (report.notes || []).filter((note) => note.visibility === 'agent').map(noteView)
});

const adminView = (report) => ({
  ...baseView(report),
  customer: report.customer
    ? { id: report.customer.id, fullName: report.customer.fullName, email: report.customer.email }
    : null,
  assignedAgentId: report.assignedAgentId,
  assignedStaffId: report.assignedStaffId,
  visibilityClassification: report.visibilityClassification,
  sharedWithAgent: report.sharedWithAgent,
  notes: (report.notes || []).map(noteView)
});

const withRelations = [
  { model: Property, as: 'property', attributes: ['id', 'name', 'city', 'neighborhood'] },
  { model: User, as: 'customer', attributes: ['id', 'fullName', 'email'] },
  { model: ProblemReportNote, as: 'notes' }
];
const noteOrder = [[{ model: ProblemReportNote, as: 'notes' }, 'createdAt', 'ASC']];

const audit = (req, action, report, metadata = {}) => AdminAuditEvent.create({
  actorId: req.user.id,
  action,
  entityType: 'ProblemReport',
  entityId: report.id,
  metadata,
  ipAddress: req.ip
});

const validation = (req, res) => {
  const errors = validationResult(req);
  if (errors.isEmpty()) return false;
  res.status(400).json({ error: 'Validation failed', details: errors.array() });
  return true;
};

router.post('/', authenticateToken, requireRole('CUSTOMER'), submissionLimiter,
  acceptFiles('evidence'), [
    body('bookingId').isUUID(),
    body('category').isIn(ProblemReport.categories),
    body('severity').optional().isIn(['general', 'urgent']),
    body('description').isString().trim().isLength({ min: 10, max: 3000 })
  ], async (req, res) => {
    if (validation(req, res)) return;
    let stored = [];
    try {
      const booking = await Booking.findOne({
        where: { id: req.body.bookingId, customerId: req.user.id },
        include: [{ model: Property, as: 'property' }]
      });
      if (!booking || booking.property?.businessModel !== 'bookable') {
        return res.status(403).json({ error: 'You can only report a problem about your own stay' });
      }
      if (!['confirmed', 'completed'].includes(booking.status)
        || (booking.status === 'confirmed' && new Date(booking.checkIn).getTime() > Date.now())) {
        return res.status(403).json({ error: 'Problems can be reported once your stay has started' });
      }
      const description = cleanText(req.body.description, 3000);
      if (description.length < 10) {
        return res.status(400).json({ error: 'Please describe the problem in at least 10 characters' });
      }
      stored = await storeFiles(req.files, 'report-evidence', { allowPdf: true });
      const sensitive = ProblemReport.sensitiveCategories.includes(req.body.category)
        || sensitiveWords.test(description);
      const report = await ProblemReport.create({
        reference: makeReference(),
        bookingId: booking.id,
        propertyId: booking.propertyId,
        customerId: req.user.id,
        assignedAgentId: booking.property.agentId,
        category: req.body.category,
        severity: req.body.severity === 'urgent' ? 'urgent' : 'general',
        description,
        evidenceFiles: stored,
        visibilityClassification: sensitive ? 'sensitive' : 'ordinary',
        sharedWithAgent: !sensitive,
        status: 'open'
      });

      await notify(req.user.id, 'CUSTOMER', 'Report received',
        'Your concern has been received. You can track its progress in your account.',
        '/account/reports', 'Track report');
      const priority = report.severity === 'urgent' || sensitive;
      await notifyAdmins(
        priority ? 'Priority: new customer problem report' : 'New customer problem report',
        'New customer problem report received.',
        '/admin/reports'
      );
      if (!sensitive) {
        await notify(booking.property.agentId, 'STAY_AGENT', 'Customer concern reported',
          'A customer has reported a concern about your property.', '/agent/reports', 'View report');
      }
      res.status(201).json({
        message: 'Report received',
        report: customerView({ ...report.toJSON(), id: report.id, property: booking.property, notes: [] })
      });
    } catch (error) {
      await removeFiles('report-evidence', stored);
      if (error.status === 400) return res.status(400).json({ error: error.message });
      console.error('Submit problem report error:', error.message);
      res.status(500).json({ error: 'Failed to submit report' });
    }
  });

router.get('/mine', authenticateToken, requireRole('CUSTOMER'), async (req, res) => {
  try {
    const where = { customerId: req.user.id };
    if (req.query.bookingId) where.bookingId = String(req.query.bookingId);
    const reports = await ProblemReport.findAll({
      where, include: withRelations, order: [['createdAt', 'DESC'], ...noteOrder]
    });
    res.json({ reports: reports.map(customerView) });
  } catch (error) {
    console.error('List own reports error:', error.message);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

router.post('/:id/reply', authenticateToken, requireRole('CUSTOMER'), [
  body('body').isString().trim().isLength({ min: 2, max: 2000 })
], async (req, res) => {
  if (validation(req, res)) return;
  try {
    const report = await ProblemReport.findOne({ where: { id: req.params.id, customerId: req.user.id } });
    if (!report) return res.status(404).json({ error: 'Report not found' });
    if (report.status === 'closed') return res.status(409).json({ error: 'This report is closed' });
    await ProblemReportNote.create({
      reportId: report.id, authorId: req.user.id, authorRole: 'CUSTOMER',
      visibility: 'customer', kind: 'reply', body: cleanText(req.body.body, 2000)
    });
    if (report.status === 'awaiting_customer') await report.update({ status: 'under_review' });
    await notifyAdmins('Customer replied to a report', 'A customer replied to a problem report.', '/admin/reports');
    res.status(201).json({ message: 'Reply sent' });
  } catch (error) {
    console.error('Customer report reply error:', error.message);
    res.status(500).json({ error: 'Failed to send reply' });
  }
});

// Agents only ever see ordinary reports for their own properties that admin allows them to see.
const agentScope = (req) => ({
  assignedAgentId: req.user.id,
  sharedWithAgent: true
});

router.get('/agent', authenticateToken, requireRole('STAY_AGENT', 'RENTAL_AGENT'), async (req, res) => {
  try {
    const reports = await ProblemReport.findAll({
      where: agentScope(req), include: withRelations, order: [['createdAt', 'DESC'], ...noteOrder]
    });
    res.json({ reports: reports.map(agentView) });
  } catch (error) {
    console.error('List agent reports error:', error.message);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

router.post('/agent/:id/reply', authenticateToken, requireRole('STAY_AGENT', 'RENTAL_AGENT'), [
  body('body').isString().trim().isLength({ min: 2, max: 2000 }),
  body('kind').optional().isIn(['reply', 'resolution'])
], async (req, res) => {
  if (validation(req, res)) return;
  try {
    const report = await ProblemReport.findOne({ where: { id: req.params.id, ...agentScope(req) } });
    if (!report) return res.status(404).json({ error: 'Report not found' });
    if (report.status === 'closed') return res.status(409).json({ error: 'This report is closed' });
    await ProblemReportNote.create({
      reportId: report.id, authorId: req.user.id, authorRole: req.user.role,
      visibility: 'agent', kind: req.body.kind || 'reply', body: cleanText(req.body.body, 2000)
    });
    if (report.status === 'awaiting_agent') await report.update({ status: 'under_review' });
    await notifyAdmins('Agent responded to a report', 'An agent responded to a problem report.', '/admin/reports');
    res.status(201).json({ message: 'Response recorded' });
  } catch (error) {
    console.error('Agent report reply error:', error.message);
    res.status(500).json({ error: 'Failed to record response' });
  }
});

router.get('/:id/evidence/:name', authenticateToken, async (req, res) => {
  try {
    const target = filePath('report-evidence', req.params.name);
    const report = await ProblemReport.findByPk(req.params.id);
    const allowed = report && target
      && (req.user.role === 'ADMIN'
        || report.customerId === req.user.id
        || (report.assignedAgentId === req.user.id && report.sharedWithAgent))
      && (report.evidenceFiles || []).includes(req.params.name);
    if (!allowed || !fs.existsSync(target)) return res.status(404).json({ error: 'File not found' });
    res.set('Cache-Control', 'private, no-store');
    res.set('X-Content-Type-Options', 'nosniff');
    res.sendFile(target);
  } catch (error) {
    console.error('Serve evidence error:', error.message);
    res.status(500).json({ error: 'Failed to load file' });
  }
});

router.get('/admin', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const where = {};
    if (ProblemReport.categories.includes(req.query.category)) where.category = req.query.category;
    if (ProblemReport.statuses.includes(req.query.status)) where.status = req.query.status;
    if (['general', 'urgent'].includes(req.query.severity)) where.severity = req.query.severity;
    if (['ordinary', 'sensitive'].includes(req.query.classification)) {
      where.visibilityClassification = req.query.classification;
    }
    if (req.query.propertyId) where.propertyId = String(req.query.propertyId);
    const reports = await ProblemReport.findAll({
      where, include: withRelations, order: [['createdAt', 'DESC'], ...noteOrder], limit: 200
    });
    const [open, urgent, sensitive] = await Promise.all([
      ProblemReport.count({ where: { status: { [Op.notIn]: ['resolved', 'closed'] } } }),
      ProblemReport.count({ where: { severity: 'urgent', status: { [Op.notIn]: ['resolved', 'closed'] } } }),
      ProblemReport.count({ where: { visibilityClassification: 'sensitive', status: { [Op.notIn]: ['resolved', 'closed'] } } })
    ]);
    res.json({ reports: reports.map(adminView), stats: { open, urgent, sensitive } });
  } catch (error) {
    console.error('Admin list reports error:', error.message);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

router.patch('/admin/:id', authenticateToken, requireRole('ADMIN'), [
  body('status').optional().isIn(ProblemReport.statuses),
  body('assignedStaffId').optional({ nullable: true }).isUUID(),
  body('sharedWithAgent').optional().isBoolean(),
  body('escalate').optional().isBoolean()
], async (req, res) => {
  if (validation(req, res)) return;
  try {
    const result = await sequelize.transaction(async (transaction) => {
      const report = await ProblemReport.findByPk(req.params.id, { transaction });
      if (!report) return null;
      const changes = {};
      if (req.body.status) {
        changes.status = req.body.status;
        changes.resolvedAt = ['resolved', 'closed'].includes(req.body.status) ? new Date() : null;
      }
      if (req.body.assignedStaffId) {
        const staff = await User.findOne({ where: { id: req.body.assignedStaffId, role: 'ADMIN' }, transaction });
        if (!staff) return { invalid: 'Cases can only be assigned to HavenLink staff' };
        changes.assignedStaffId = staff.id;
      }
      if (req.body.sharedWithAgent !== undefined) {
        changes.sharedWithAgent = req.body.sharedWithAgent === true || req.body.sharedWithAgent === 'true';
      }
      if (req.body.escalate === true || req.body.escalate === 'true') changes.severity = 'urgent';
      await report.update(changes, { transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'PROBLEM_REPORT_UPDATED', entityType: 'ProblemReport',
        entityId: report.id, metadata: changes, ipAddress: req.ip
      }, { transaction });
      return { report, changes };
    });
    if (!result) return res.status(404).json({ error: 'Report not found' });
    if (result.invalid) return res.status(400).json({ error: result.invalid });
    if (result.changes.status) {
      await notify(result.report.customerId, 'CUSTOMER', 'Report updated',
        'Your HavenLink report has been updated.', '/account/reports', 'Track report');
    }
    if (result.changes.sharedWithAgent && result.report.assignedAgentId) {
      await notify(result.report.assignedAgentId, 'STAY_AGENT', 'Customer concern reported',
        'A customer has reported a concern about your property.', '/agent/reports', 'View report');
    }
    res.json({ message: 'Report updated' });
  } catch (error) {
    console.error('Admin update report error:', error.message);
    res.status(500).json({ error: 'Failed to update report' });
  }
});

router.post('/admin/:id/notes', authenticateToken, requireRole('ADMIN'), [
  body('body').isString().trim().isLength({ min: 2, max: 2000 }),
  body('visibility').isIn(['internal', 'customer', 'agent'])
], async (req, res) => {
  if (validation(req, res)) return;
  try {
    const report = await ProblemReport.findByPk(req.params.id);
    if (!report) return res.status(404).json({ error: 'Report not found' });
    if (req.body.visibility === 'agent' && !report.sharedWithAgent) {
      return res.status(409).json({ error: 'Share this report with the agent before writing agent-visible notes' });
    }
    await ProblemReportNote.create({
      reportId: report.id, authorId: req.user.id, authorRole: 'ADMIN',
      visibility: req.body.visibility, kind: 'note', body: cleanText(req.body.body, 2000)
    });
    await audit(req, 'PROBLEM_REPORT_NOTE_ADDED', report, { visibility: req.body.visibility });
    if (req.body.visibility === 'customer') {
      await notify(report.customerId, 'CUSTOMER', 'Report updated',
        'Your HavenLink report has been updated.', '/account/reports', 'Track report');
    }
    if (req.body.visibility === 'agent') {
      await notify(report.assignedAgentId, 'STAY_AGENT', 'Report update',
        'There is an update on a report about your property.', '/agent/reports', 'View report');
    }
    res.status(201).json({ message: 'Note added' });
  } catch (error) {
    console.error('Admin report note error:', error.message);
    res.status(500).json({ error: 'Failed to add note' });
  }
});

module.exports = router;
