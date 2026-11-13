const express = require('express');
const { body, query, validationResult } = require('express-validator');
const { Op, UniqueConstraintError } = require('sequelize');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { Property, RentObligation, RentReceipt, User } = require('../models');
const reminders = require('../services/reminders');
const ledger = require('../services/rentLedger');
const finance = require('../services/financialManagement');

const router = express.Router();
const maxAmount = 1000000000;
const validDate = (value) => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};
const validation = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
  next();
};
const errorHandler = (error, req, res, next) => {
  if (error instanceof ledger.RentLedgerError) return res.status(error.status).json({ error: error.message });
  if (error instanceof UniqueConstraintError) return res.status(409).json({ error: 'This rent record already exists' });
  console.error('Rent ledger error:', error);
  res.status(500).json({ error: 'Unable to process rent record' });
};

router.use(authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'));

async function authorizeProperty(req, res, next) {
  try {
    const property = await Property.findByPk(req.params.propertyId);
    if (!property || property.businessModel !== 'contactUnlock' ||
        (req.user.role !== 'ADMIN' &&
          (property.agentId !== req.user.id || !req.user.hasCapability('rentalProperty')))) {
      return res.status(404).json({ error: 'Rental property not found' });
    }
    req.property = property;
    next();
  } catch (error) { next(error); }
}

async function authorizeObligation(req, res, next) {
  try {
    const obligation = await RentObligation.findByPk(req.params.obligationId);
    if (!obligation || obligation.propertyId !== req.property.id) {
      return res.status(404).json({ error: 'Rent obligation not found' });
    }
    req.obligation = obligation;
    next();
  } catch (error) { next(error); }
}

const propertyPath = '/properties/:propertyId/rent';

router.get(propertyPath, authorizeProperty, [
  query('month').optional().matches(/^\d{4}-(0[1-9]|1[0-2])$/),
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
  query('offset').optional().isInt({ min: 0, max: 100000 }).toInt()
], validation, async (req, res, next) => {
  try {
    const where = { propertyId: req.property.id };
    if (req.query.month) where.billingMonth = req.query.month;
    const { rows, count } = await RentObligation.findAndCountAll({
      where, limit: req.query.limit || 25, offset: req.query.offset || 0,
      order: [['billingMonth', 'DESC'], ['unitReference', 'ASC'], ['id', 'ASC']]
    });
    const receipts = await RentReceipt.findAll({
      where: { obligationId: { [Op.in]: rows.map((row) => row.id) } },
      order: [['paymentDate', 'DESC'], ['createdAt', 'DESC']]
    });
    res.json({
      records: rows.map((row) => ledger.describeObligation(
        row, receipts.filter((receipt) => receipt.obligationId === row.id)
      )),
      total: count, limit: req.query.limit || 25, offset: req.query.offset || 0
    });
  } catch (error) { next(error); }
});

router.post(propertyPath, authorizeProperty, [
  body('unitReference').isString().trim().isLength({ min: 1, max: 100 }),
  body('tenantReference').optional({ nullable: true }).isString().trim().isLength({ max: 200 }),
  body('billingMonth').matches(/^\d{4}-(0[1-9]|1[0-2])$/),
  body('expectedTzs').isInt({ min: 1, max: maxAmount }).toInt(),
  body('dueDate').custom(validDate)
], validation, async (req, res, next) => {
  try {
    const { unitReference, tenantReference, billingMonth, expectedTzs, dueDate } = req.body;
    const obligation = await RentObligation.create({
      propertyId: req.property.id, unitReference, tenantReference,
      billingMonth, expectedTzs, dueDate, createdById: req.user.id
    });
    res.status(201).json({ record: ledger.describeObligation(obligation, []) });
  } catch (error) { next(error); }
});

router.post(`${propertyPath}/:obligationId/receipts`, authorizeProperty, authorizeObligation, [
  body('amountTzs').isInt({ min: 1, max: maxAmount }).toInt(),
  body('paymentDate').custom(validDate),
  body('reference').optional({ nullable: true }).isString().trim().isLength({ max: 200 }),
  body('idempotencyKey').isString().trim().isLength({ min: 1, max: 200 })
], validation, async (req, res, next) => {
  try {
    const { amountTzs, paymentDate, idempotencyKey } = req.body;
    const result = await ledger.addReceipt(req.obligation.id, req.user.id, {
      amountTzs, paymentDate, idempotencyKey, reference: req.body.reference || null
    });
    if (result.created) {
      await finance.audit(req.user.id, 'RENT_RECEIPT_RECORDED', req.property,
        'RentReceipt', result.receipt.id, {
          obligationId: req.obligation.id, amountTzs: result.receipt.amountTzs
        });
    }
    res.status(result.created ? 201 : 200).json({
      receipt: { ...result.receipt.toJSON(), source: 'manualOffline', platformVerified: false }
    });
  } catch (error) { next(error); }
});

router.post(`${propertyPath}/:obligationId/receipts/:receiptId/reverse`,
  authorizeProperty, authorizeObligation, [
    body('reason').isString().trim().isLength({ min: 3, max: 500 })
  ], validation, async (req, res, next) => {
    try {
      const receipt = await RentReceipt.findOne({
        where: { id: req.params.receiptId, obligationId: req.obligation.id }
      });
      if (!receipt) return res.status(404).json({ error: 'Receipt not found' });
      const reversed = await ledger.reverseReceipt(receipt.id, req.user.id, req.body.reason);
      await finance.audit(req.user.id, 'RENT_RECEIPT_REVERSED', req.property,
        'RentReceipt', reversed.id, { reason: req.body.reason.trim() });
      res.json({ receipt: { ...reversed.toJSON(), source: 'manualOffline', platformVerified: false } });
    } catch (error) { next(error); }
  }
);

router.put(`${propertyPath}/:obligationId/tenancy`, authorizeProperty, authorizeObligation, [
  body('tenantPhone').optional({ nullable: true }).matches(/^\+255\d{9}$/),
  body('unlinkTenant').optional().isBoolean({ strict: true }),
  body('reminderOffsets').optional({ nullable: true }).isArray({ min: 1, max: 6 }),
  body('leaseEndDate').optional({ nullable: true }).custom(validDate),
  body('endTenancy').optional().isBoolean({ strict: true })
], validation, async (req, res, next) => {
  try {
    const updates = {};
    if (req.body.tenantPhone) {
      const tenant = await User.findOne({ where: { phone: req.body.tenantPhone, role: 'CUSTOMER', accountEnabled: true } });
      if (!tenant || tenant.verification !== 'verified') {
        return res.status(404).json({ error: 'No verified Haven Link customer account matches that phone number' });
      }
      updates.tenantUserId = tenant.id;
    }
    if (req.body.unlinkTenant === true) updates.tenantUserId = null;
    if (req.body.reminderOffsets !== undefined) {
      const offsets = req.body.reminderOffsets === null ? null : reminders.sanitizeOffsets(req.body.reminderOffsets);
      if (req.body.reminderOffsets !== null && !offsets) {
        return res.status(400).json({ error: 'Reminder offsets must be up to 6 whole days between -30 and 30' });
      }
      updates.reminderOffsets = offsets;
    }
    if (req.body.leaseEndDate !== undefined) updates.leaseEndDate = req.body.leaseEndDate;
    if (req.body.endTenancy === true) updates.tenancyEndedAt = new Date();
    await req.obligation.update(updates);
    await finance.audit(req.user.id, 'RENT_TENANCY_UPDATED', req.property,
      'RentObligation', req.obligation.id, { fields: Object.keys(updates) });
    res.json({
      tenancy: {
        id: req.obligation.id, tenantLinked: Boolean(req.obligation.tenantUserId),
        reminderOffsets: req.obligation.reminderOffsets, leaseEndDate: req.obligation.leaseEndDate,
        tenancyEndedAt: req.obligation.tenancyEndedAt
      }
    });
  } catch (error) { next(error); }
});

router.use(errorHandler);
module.exports = router;
