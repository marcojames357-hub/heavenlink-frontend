const express = require('express');
const { body, query, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const { authenticateToken } = require('../middleware/auth');
const {
  Notification, NotificationPreference, RentObligation, RentReceipt, Property
} = require('../models');
const { GROUPS } = require('../services/notify');

const router = express.Router();
router.use(authenticateToken);

const validation = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
  next();
};

router.get('/', [
  query('group').optional().isIn(Object.keys(GROUPS)),
  query('unread').optional().isBoolean().toBoolean(),
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
  query('offset').optional().isInt({ min: 0, max: 100000 }).toInt()
], validation, async (req, res, next) => {
  try {
    const where = { userId: req.user.id };
    if (req.query.group) where.category = { [Op.in]: GROUPS[req.query.group] };
    if (req.query.unread === true) where.isRead = false;
    const { rows, count } = await Notification.findAndCountAll({
      where, order: [['createdAt', 'DESC']],
      limit: req.query.limit || 30, offset: req.query.offset || 0
    });
    res.json({ notifications: rows, total: count });
  } catch (error) { next(error); }
});

router.get('/unread-count', async (req, res, next) => {
  try {
    res.json({ unread: await Notification.count({ where: { userId: req.user.id, isRead: false } }) });
  } catch (error) { next(error); }
});

router.put('/read', [
  body('ids').optional().isArray({ max: 200 }),
  body('ids.*').isUUID()
], validation, async (req, res, next) => {
  try {
    const where = { userId: req.user.id, isRead: false };
    if (req.body.ids) where.id = { [Op.in]: req.body.ids };
    const [updated] = await Notification.update({ isRead: true, readAt: new Date() }, { where });
    res.json({ updated });
  } catch (error) { next(error); }
});

router.get('/preferences', async (req, res, next) => {
  try {
    const [preference] = await NotificationPreference.findOrCreate({ where: { userId: req.user.id } });
    res.json({
      preferences: {
        inApp: true, sms: preference.sms, email: preference.email,
        mutedCategories: preference.mutedCategories
      }
    });
  } catch (error) { next(error); }
});

router.put('/preferences', [
  body('sms').optional().isBoolean({ strict: true }),
  body('email').optional().isBoolean({ strict: true }),
  body('mutedCategories').optional().isArray({ max: 12 }),
  body('mutedCategories.*').isIn(['booking', 'checkin', 'checkout', 'rent', 'finance', 'message', 'review', 'report', 'payment'])
], validation, async (req, res, next) => {
  try {
    const [preference] = await NotificationPreference.findOrCreate({ where: { userId: req.user.id } });
    const updates = {};
    for (const field of ['sms', 'email', 'mutedCategories']) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    await preference.update(updates);
    res.json({
      preferences: {
        inApp: true, sms: preference.sms, email: preference.email,
        mutedCategories: preference.mutedCategories
      }
    });
  } catch (error) { next(error); }
});

// Only tenancies an agent linked to this account appear; unlock customers see nothing here.
router.get('/rental-statements', async (req, res, next) => {
  try {
    const obligations = await RentObligation.findAll({
      where: { tenantUserId: req.user.id },
      include: [{ model: Property, as: 'property', attributes: ['id', 'name'] }],
      order: [['dueDate', 'DESC']], limit: 100
    });
    const receipts = await RentReceipt.findAll({
      where: { obligationId: { [Op.in]: obligations.map((item) => item.id) }, reversedAt: null }
    });
    res.json({
      statements: obligations.map((item) => {
        const paid = receipts.filter((receipt) => receipt.obligationId === item.id)
          .reduce((sum, receipt) => sum + receipt.amountTzs, 0);
        return {
          id: item.id, property: item.property.name, unit: item.unitReference,
          billingMonth: item.billingMonth, dueDate: item.dueDate, expectedTzs: item.expectedTzs,
          // Payments recorded by the agent, which may have happened outside Haven Link.
          recordedPaidTzs: paid, outstandingTzs: Math.max(0, item.expectedTzs - paid),
          tenancyEnded: Boolean(item.tenancyEndedAt)
        };
      })
    });
  } catch (error) { next(error); }
});

router.put('/:id/read', async (req, res, next) => {
  try {
    const [updated] = await Notification.update(
      { isRead: true, readAt: new Date() }, { where: { id: req.params.id, userId: req.user.id } }
    );
    if (!updated) return res.status(404).json({ error: 'Notification not found' });
    res.json({ updated });
  } catch (error) { next(error); }
});

module.exports = router;
