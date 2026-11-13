const express = require('express');
const { body, query, validationResult } = require('express-validator');
const { Op, UniqueConstraintError } = require('sequelize');
const { authenticateToken, requireRole } = require('../middleware/auth');
const {
  Property, PropertyExpense, UtilityBill, StaffObligation, FinancialPayment,
  FinancialAlert
} = require('../models');
const finance = require('../services/financialManagement');

const router = express.Router();
const maxAmount = 1000000000;
const categories = {
  propertyExpense: ['maintenance', 'cleaning', 'security', 'supplies', 'administration', 'other'],
  utilityBill: ['electricity', 'water', 'internet', 'tv', 'streaming', 'gas', 'waste', 'security', 'serviceCharge', 'other'],
  staffFrequency: ['monthly', 'weekly', 'daily', 'oneTime']
};
const validDate = (value) => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
  next();
};
const handleError = (error, req, res, next) => {
  if (error.status) return res.status(error.status).json({ error: error.message });
  if (error instanceof UniqueConstraintError) return res.status(409).json({ error: 'A record with these details already exists' });
  console.error('Financial management error:', error);
  res.status(500).json({ error: 'Unable to process financial records' });
};

router.use(authenticateToken);

async function authorizeProperty(req, res, next) {
  try {
    const property = await Property.findByPk(req.params.propertyId);
    if (!property) return res.status(404).json({ error: 'Property not found' });
    if (req.user.role !== 'ADMIN' &&
        (property.agentId !== req.user.id ||
          (property.businessModel === 'contactUnlock' && !req.user.hasCapability('rentalProperty')) ||
          (property.businessModel === 'bookable' && !req.user.hasCapability('accommodationBooking')))) {
      return res.status(404).json({ error: 'Property not found' });
    }
    if (req.user.role !== 'ADMIN' &&
        ((property.businessModel === 'contactUnlock' && req.user.role !== 'RENTAL_AGENT') ||
         (property.businessModel === 'bookable' && req.user.role !== 'STAY_AGENT'))) {
      return res.status(404).json({ error: 'Property not found' });
    }
    req.property = property;
    next();
  } catch (error) { next(error); }
}

async function authorizeFinancialRecord(req, res, next) {
  try {
    const Model = finance.TYPES[req.params.recordType];
    if (!Model) return res.status(400).json({ error: 'Invalid financial record type' });
    const record = await Model.findOne({
      where: { id: req.params.recordId, propertyId: req.property.id }
    });
    if (!record) return res.status(404).json({ error: 'Financial record not found' });
    req.financialRecord = record;
    next();
  } catch (error) { next(error); }
}

router.get('/dashboard', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), [
  query('businessModel').isIn(['contactUnlock', 'bookable']),
  query('propertyId').optional().isUUID(),
  query('from').optional().custom(validDate),
  query('to').optional().custom(validDate),
  query('limit').optional().isInt({ min: 1, max: 100 })
], validate, async (req, res, next) => {
  try {
    if (req.query.from && req.query.to && req.query.from > req.query.to) {
      return res.status(400).json({ error: 'from must not be after to' });
    }
    if (req.user.role !== 'ADMIN') {
      const expectedRole = req.query.businessModel === 'bookable' ? 'STAY_AGENT' : 'RENTAL_AGENT';
      if (req.user.role !== expectedRole ||
          !req.user.hasCapability(req.query.businessModel === 'bookable' ? 'accommodationBooking' : 'rentalProperty')) {
        return res.status(403).json({ error: 'Insufficient permissions for this financial dashboard' });
      }
    }
    const data = await finance.getDashboard({
      user: req.user, businessModel: req.query.businessModel, propertyId: req.query.propertyId,
      from: req.query.from, to: req.query.to
    });
    res.json(data);
  } catch (error) { next(error); }
});

router.get('/admin/overview', requireRole('ADMIN'), async (req, res, next) => {
  try { res.json(await finance.adminOverview()); } catch (error) { next(error); }
});

router.get('/properties/:propertyId/expenses', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
  authorizeProperty, async (req, res, next) => {
    try {
      const records = await PropertyExpense.findAll({
        where: { propertyId: req.property.id, reversedAt: { [Op.is]: null } },
        order: [['expenseDate', 'DESC']], limit: 100
      });
      res.json({ records: await Promise.all(records.map((record) =>
        finance.serializeObligation('propertyExpense', record))) });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/expenses', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
  authorizeProperty, [
    body('unitReference').optional({ nullable: true }).isString().trim().isLength({ max: 100 }),
    body('title').isString().trim().isLength({ min: 2, max: 200 }),
    body('category').isIn(categories.propertyExpense),
    body('amountTzs').isInt({ min: 1, max: maxAmount }).toInt(),
    body('expenseDate').custom(validDate),
    body('description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 })
  ], validate, async (req, res, next) => {
    try {
      const record = await PropertyExpense.create({
        propertyId: req.property.id, createdById: req.user.id,
        unitReference: req.body.unitReference || null,
        title: req.body.title.trim(), category: req.body.category,
        amountTzs: req.body.amountTzs, expenseDate: req.body.expenseDate,
        description: req.body.description?.trim() || null
      });
      await finance.audit(req.user.id, 'FINANCIAL_EXPENSE_CREATED', req.property,
        'PropertyExpense', record.id, { amountTzs: record.amountTzs, category: record.category });
      res.status(201).json({ record: { ...record.toJSON(), paidTzs: 0, status: 'unpaid' } });
    } catch (error) { next(error); }
  }
);

router.patch('/properties/:propertyId/expenses/:recordId',
  requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), authorizeProperty, [
    body('title').optional().isString().trim().isLength({ min: 2, max: 200 }),
    body('category').optional().isIn(categories.propertyExpense),
    body('amountTzs').optional().isInt({ min: 1, max: maxAmount }).toInt(),
    body('expenseDate').optional().custom(validDate),
    body('unitReference').optional({ nullable: true }).isString().trim().isLength({ max: 100 }),
    body('description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 })
  ], validate, async (req, res, next) => {
    try {
      const record = await PropertyExpense.findOne({
        where: { id: req.params.recordId, propertyId: req.property.id, reversedAt: { [Op.is]: null } }
      });
      if (!record) return res.status(404).json({ error: 'Expense not found' });
      const previous = {
        title: record.title, category: record.category, amountTzs: record.amountTzs,
        expenseDate: record.expenseDate, unitReference: record.unitReference,
        description: record.description
      };
      const changes = {};
      for (const key of Object.keys(previous)) {
        if (Object.hasOwn(req.body, key)) {
          changes[key] = typeof req.body[key] === 'string' ? req.body[key].trim() : req.body[key];
        }
      }
      if (!Object.keys(changes).length) {
        return res.status(400).json({ error: 'Provide at least one expense field to update' });
      }
      await record.update(changes);
      await finance.audit(req.user.id, 'FINANCIAL_EXPENSE_UPDATED', req.property,
        'PropertyExpense', record.id, { previous, changes });
      res.json({ record: { ...record.toJSON(), paidTzs: await finance.paidAmount('propertyExpense', record.id) } });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/bills', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
  authorizeProperty, [
    body('unitReference').optional({ nullable: true }).isString().trim().isLength({ max: 100 }),
    body('category').isIn(categories.utilityBill),
    body('provider').isString().trim().isLength({ min: 1, max: 200 }),
    body('billingMonth').matches(/^\d{4}-(0[1-9]|1[0-2])$/),
    body('amountTzs').isInt({ min: 1, max: maxAmount }).toInt(),
    body('dueDate').custom(validDate),
    body('notes').optional({ nullable: true }).isString().trim().isLength({ max: 1000 }),
    body('recurring').optional().isBoolean().toBoolean()
  ], validate, async (req, res, next) => {
    try {
      const record = await UtilityBill.create({
        propertyId: req.property.id, createdById: req.user.id,
        unitReference: req.body.unitReference || null,
        category: req.body.category, provider: req.body.provider.trim(),
        billingMonth: req.body.billingMonth, amountTzs: req.body.amountTzs,
        dueDate: req.body.dueDate, notes: req.body.notes?.trim() || null,
        recurring: req.body.recurring === true
      });
      await finance.audit(req.user.id, 'UTILITY_BILL_CREATED', req.property,
        'UtilityBill', record.id, { amountTzs: record.amountTzs, category: record.category });
      res.status(201).json({ record: { ...record.toJSON(), paidTzs: 0, status: 'unpaid' } });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/staff', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
  authorizeProperty, [
    body('staffName').isString().trim().isLength({ min: 2, max: 200 }),
    body('staffRole').isString().trim().isLength({ min: 2, max: 100 }),
    body('frequency').isIn(categories.staffFrequency),
    body('amountTzs').isInt({ min: 1, max: maxAmount }).toInt(),
    body('dueDate').custom(validDate)
  ], validate, async (req, res, next) => {
    try {
      const record = await StaffObligation.create({
        propertyId: req.property.id, createdById: req.user.id,
        staffName: req.body.staffName.trim(), staffRole: req.body.staffRole.trim(),
        frequency: req.body.frequency, amountTzs: req.body.amountTzs,
        dueDate: req.body.dueDate
      });
      await finance.audit(req.user.id, 'STAFF_OBLIGATION_CREATED', req.property,
        'StaffObligation', record.id, { amountTzs: record.amountTzs });
      res.status(201).json({ record: { ...record.toJSON(), paidTzs: 0, status: 'unpaid' } });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/:recordType/:recordId/payments',
  requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), authorizeProperty, authorizeFinancialRecord, [
    body('amountTzs').isInt({ min: 1, max: maxAmount }).toInt(),
    body('paymentDate').custom(validDate),
    body('method').optional({ nullable: true }).isString().trim().isLength({ max: 100 }),
    body('reference').optional({ nullable: true }).isString().trim().isLength({ max: 200 }),
    body('idempotencyKey').isString().trim().isLength({ min: 1, max: 200 })
  ], validate, async (req, res, next) => {
    try {
      const result = await finance.recordPayment({
        type: req.params.recordType, recordId: req.financialRecord.id,
        propertyId: req.property.id, actorId: req.user.id,
        input: {
          amountTzs: req.body.amountTzs, paymentDate: req.body.paymentDate,
          method: req.body.method || null, reference: req.body.reference || null,
          idempotencyKey: req.body.idempotencyKey
        }
      });
      if (result.created) {
        await finance.audit(req.user.id, 'FINANCIAL_PAYMENT_RECORDED', req.property,
          'FinancialPayment', result.payment.id, {
            recordType: req.params.recordType, recordId: req.financialRecord.id,
            amountTzs: result.payment.amountTzs
          });
      }
      res.status(result.created ? 201 : 200).json({
        payment: { ...result.payment.toJSON(), source: 'manualOffline', platformVerified: false }
      });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/payments/:paymentId/reverse',
  requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), authorizeProperty, [
    body('reason').isString().trim().isLength({ min: 3, max: 500 })
  ], validate, async (req, res, next) => {
    try {
      const payment = await FinancialPayment.findOne({
        where: { id: req.params.paymentId, propertyId: req.property.id }
      });
      if (!payment) return res.status(404).json({ error: 'Financial payment not found' });
      const reversed = await finance.reversePayment(payment.id, req.user.id, req.body.reason);
      await finance.audit(req.user.id, 'FINANCIAL_PAYMENT_REVERSED', req.property,
        'FinancialPayment', reversed.id, { reason: req.body.reason.trim() });
      res.json({ payment: reversed });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/expenses/:recordId/reverse',
  requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), authorizeProperty, [
    body('reason').isString().trim().isLength({ min: 3, max: 500 })
  ], validate, async (req, res, next) => {
    try {
      const record = await PropertyExpense.findOne({
        where: { id: req.params.recordId, propertyId: req.property.id }
      });
      if (!record) return res.status(404).json({ error: 'Expense not found' });
      if (record.reversedAt) return res.status(409).json({ error: 'Expense is already reversed' });
      if (await finance.paidAmount('propertyExpense', record.id) > 0) {
        return res.status(409).json({ error: 'Reverse its recorded payments before reversing this expense' });
      }
      await record.update({
        reversedAt: new Date(), reversedById: req.user.id, reversalReason: req.body.reason.trim()
      });
      await finance.audit(req.user.id, 'FINANCIAL_EXPENSE_REVERSED', req.property,
        'PropertyExpense', record.id, { reason: req.body.reason.trim() });
      res.json({ record });
    } catch (error) { next(error); }
  }
);

router.post('/properties/:propertyId/:recordType/:recordId/reverse',
  requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), authorizeProperty, [
    body('reason').isString().trim().isLength({ min: 3, max: 500 })
  ], validate, async (req, res, next) => {
    try {
      const Model = finance.TYPES[req.params.recordType];
      if (!Model || req.params.recordType === 'propertyExpense') {
        return res.status(400).json({ error: 'Invalid financial record type' });
      }
      const record = await Model.findOne({
        where: { id: req.params.recordId, propertyId: req.property.id }
      });
      if (!record) return res.status(404).json({ error: 'Financial record not found' });
      if (record.reversedAt) return res.status(409).json({ error: 'Financial record is already reversed' });
      const paid = await finance.paidAmount(req.params.recordType, record.id);
      if (paid > 0) {
        return res.status(409).json({ error: 'Reverse its recorded payments before reversing this financial record' });
      }
      await record.update({
        reversedAt: new Date(), reversedById: req.user.id, reversalReason: req.body.reason.trim()
      });
      await finance.audit(req.user.id, 'FINANCIAL_RECORD_REVERSED', req.property,
        req.params.recordType, record.id, { reason: req.body.reason.trim() });
      res.json({ record });
    } catch (error) { next(error); }
  }
);

router.get('/alerts', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), async (req, res, next) => {
  try {
    const where = { resolvedAt: { [Op.is]: null } };
    if (req.user.role !== 'ADMIN') where.ownerId = req.user.id;
    if (req.query.unread === 'true') where.isRead = false;
    const alerts = await FinancialAlert.findAll({
      where, include: [{ model: Property, as: 'property', attributes: ['id', 'name'] }],
      order: [['createdAt', 'DESC']], limit: 100
    });
    res.json({ alerts });
  } catch (error) { next(error); }
});

router.patch('/alerts/:alertId/read', requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), async (req, res, next) => {
  try {
    const where = { id: req.params.alertId };
    if (req.user.role !== 'ADMIN') where.ownerId = req.user.id;
    const alert = await FinancialAlert.findOne({ where });
    if (!alert) return res.status(404).json({ error: 'Financial alert not found' });
    await alert.update({ isRead: true });
    res.json({ alert });
  } catch (error) { next(error); }
});

router.use(handleError);
module.exports = router;
