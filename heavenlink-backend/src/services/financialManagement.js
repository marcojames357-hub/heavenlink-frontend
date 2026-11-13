const { Op, Transaction } = require('sequelize');
const {
  sequelize, Property, Booking, PaymentTransaction, RentObligation, RentReceipt,
  PropertyExpense, UtilityBill, StaffObligation, FinancialPayment, FinancialAlert,
  Notification, AdminAuditEvent, User
} = require('../models');
const { darEsSalaamDate } = require('./rentLedger');

const TYPES = {
  propertyExpense: PropertyExpense,
  utilityBill: UtilityBill,
  staffObligation: StaffObligation
};
const dateOnly = (value) => value instanceof Date
  ? value.toISOString().slice(0, 10)
  : String(value).slice(0, 10);

const paidAmount = async (type, id, transaction) =>
  await FinancialPayment.sum('amountTzs', {
    where: { recordType: type, recordId: id, reversedAt: { [Op.is]: null } },
    transaction
  }) || 0;

const obligationStatus = (total, paid, dueDate, today = darEsSalaamDate()) => {
  if (paid >= total) return 'paid';
  if (dueDate < today) return 'overdue';
  return paid > 0 ? 'partiallyPaid' : 'unpaid';
};

const serializeObligation = async (type, record) => ({
  ...record.toJSON(),
  paidTzs: await paidAmount(type, record.id),
  status: obligationStatus(record.amountTzs, await paidAmount(type, record.id), record.dueDate)
});

async function recordPayment({ type, recordId, propertyId, actorId, input }) {
  const Model = TYPES[type];
  if (!Model) throw Object.assign(new Error('Invalid financial record type'), { status: 400 });
  return sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
    const previous = await FinancialPayment.findOne({
      where: { createdById: actorId, idempotencyKey: input.idempotencyKey }, transaction
    });
    if (previous) {
      if (previous.recordType !== type || previous.recordId !== recordId ||
          previous.amountTzs !== input.amountTzs || previous.paymentDate !== input.paymentDate ||
          previous.method !== input.method || previous.reference !== input.reference) {
        throw Object.assign(new Error('Idempotency key was already used for a different payment'), { status: 409 });
      }
      return { payment: previous, created: false };
    }

    const record = await Model.findOne({ where: { id: recordId, propertyId }, transaction });
    if (!record || record.reversedAt) throw Object.assign(new Error('Financial record not found'), { status: 404 });
    const paidTzs = await paidAmount(type, record.id, transaction);
    if (input.amountTzs > record.amountTzs - paidTzs) {
      throw Object.assign(new Error('Payment exceeds the outstanding balance'), { status: 409 });
    }
    const payment = await FinancialPayment.create({
      propertyId, recordType: type, recordId, createdById: actorId, ...input
    }, { transaction });
    return { payment, created: true };
  });
}

async function reversePayment(paymentId, actorId, reason) {
  return sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
    const payment = await FinancialPayment.findByPk(paymentId, { transaction });
    if (!payment) throw Object.assign(new Error('Payment not found'), { status: 404 });
    if (payment.reversedAt) throw Object.assign(new Error('Payment is already reversed'), { status: 409 });
    await payment.update({
      reversedAt: new Date(), reversedById: actorId, reversalReason: reason
    }, { transaction });
    return payment;
  });
}

async function audit(actorId, action, property, entityType, entityId, metadata = {}) {
  await AdminAuditEvent.create({
    actorId, action, entityType, entityId: String(entityId),
    metadata: { propertyId: property.id, ...metadata }
  });
}

async function refreshPropertyAlerts(property, ownerId) {
  const today = darEsSalaamDate();
  const soon = new Date(`${today}T00:00:00Z`);
  soon.setUTCDate(soon.getUTCDate() + 7);
  const soonDate = soon.toISOString().slice(0, 10);
  const records = [];
  const rent = await RentObligation.findAll({ where: { propertyId: property.id } });
  for (const obligation of rent) {
    const receipts = await RentReceipt.findAll({ where: { obligationId: obligation.id } });
    const paid = receipts.filter((receipt) => !receipt.reversedAt)
      .reduce((sum, receipt) => sum + receipt.amountTzs, 0);
    const outstanding = obligation.expectedTzs - paid;
    if (outstanding <= 0) continue;
    const overdue = obligation.dueDate < today;
    const dueSoon = obligation.dueDate >= today && obligation.dueDate <= soonDate;
    if (overdue || dueSoon) records.push({
      alertKey: `rent:${obligation.id}`, recordType: 'rentObligation', recordId: obligation.id,
      title: overdue ? 'Rent overdue' : 'Rent due soon',
      description: `${obligation.unitReference} has TZS ${outstanding} outstanding for ${obligation.billingMonth}.`,
      severity: overdue ? 'critical' : 'warning'
    });
  }
  const expenses = await PropertyExpense.findAll({
    where: { propertyId: property.id, reversedAt: { [Op.is]: null } }
  });
  for (const expense of expenses) {
    const paid = await paidAmount('propertyExpense', expense.id);
    if (paid >= expense.amountTzs) continue;
    records.push({
      alertKey: `expense:${expense.id}`, recordType: 'propertyExpense', recordId: expense.id,
      title: 'Unpaid operating expense',
      description: `${property.name} has an unpaid ${expense.category} expense of TZS ${expense.amountTzs - paid}.`,
      severity: expense.expenseDate < today ? 'warning' : 'informational'
    });
  }
  for (const [type, Model, title] of [
    ['utilityBill', UtilityBill, 'Utility bill'], ['staffObligation', StaffObligation, 'Staff payment']
  ]) {
    const rows = await Model.findAll({
      where: { propertyId: property.id, reversedAt: { [Op.is]: null } }
    });
    for (const row of rows) {
      const paid = await paidAmount(type, row.id);
      if (paid >= row.amountTzs) continue;
      const overdue = row.dueDate < today;
      const dueSoon = row.dueDate >= today && row.dueDate <= soonDate;
      if (overdue || dueSoon) records.push({
        alertKey: `${type}:${row.id}`, recordType: type, recordId: row.id,
        title: overdue ? `${title} overdue` : `${title} due soon`,
        description: `${property.name} has TZS ${row.amountTzs - paid} outstanding, due ${row.dueDate}.`,
        severity: overdue ? 'critical' : 'warning'
      });
    }
  }
  const activeKeys = [];
  for (const candidate of records) {
    activeKeys.push(candidate.alertKey);
    const [alert, created] = await FinancialAlert.findOrCreate({
      where: { propertyId: property.id, alertKey: candidate.alertKey },
      defaults: { ...candidate, ownerId, propertyId: property.id }
    });
    if (!created) {
      await alert.update({
        ownerId, recordType: candidate.recordType, recordId: candidate.recordId,
        title: candidate.title, description: candidate.description,
        severity: candidate.severity, resolvedAt: null
      });
    } else {
      await Notification.create({
        userId: ownerId, audience: property.businessModel === 'bookable' ? 'STAY_AGENT' : 'RENTAL_AGENT',
        title: candidate.title, message: `${property.name}: ${candidate.description}`,
        actionUrl: '/financial-management', actionLabel: 'Open financial management'
      });
    }
  }
  if (property.businessModel === 'bookable') {
    const bookings = await Booking.findAll({
      where: { propertyId: property.id, status: { [Op.ne]: 'cancelled' } },
      include: [{ model: PaymentTransaction, as: 'transaction', required: false,
        attributes: ['id', 'status'] }],
      order: [['createdAt', 'DESC']], limit: 500
    });
    for (const booking of bookings) {
      let candidate;
      if (booking.transaction?.status === 'refunded') {
        candidate = {
          alertKey: `refund:${booking.transaction.id}`, recordType: 'booking',
          recordId: booking.id, title: 'Booking refund requires review',
          description: `${property.name} has a refunded booking payment that needs financial review.`,
          severity: 'critical'
        };
      } else if (booking.status === 'pending') {
        candidate = {
          alertKey: `booking:${booking.id}`, recordType: 'booking',
          recordId: booking.id, title: 'Booking payment outstanding',
          description: `${property.name} has a booking awaiting payment confirmation.`,
          severity: 'warning'
        };
      }
      if (candidate) {
        activeKeys.push(candidate.alertKey);
        const [alert, created] = await FinancialAlert.findOrCreate({
          where: { propertyId: property.id, alertKey: candidate.alertKey },
          defaults: { ...candidate, ownerId, propertyId: property.id }
        });
        if (!created) {
          await alert.update({
            ownerId, recordType: candidate.recordType, recordId: candidate.recordId,
            title: candidate.title, description: candidate.description,
            severity: candidate.severity, resolvedAt: null
          });
        } else {
          await Notification.create({
            userId: ownerId, audience: 'STAY_AGENT', title: candidate.title,
            message: `${property.name}: ${candidate.description}`,
            actionUrl: '/financial-management', actionLabel: 'Open financial management'
          });
        }
      }
    }
  }
  await FinancialAlert.update(
    { resolvedAt: new Date() },
    {
      where: {
        propertyId: property.id, resolvedAt: { [Op.is]: null },
        alertKey: { [Op.notIn]: activeKeys.length ? activeKeys : ['__none__'] }
      }
    }
  );
}

async function getDashboard({ user, businessModel, propertyId, from, to }) {
  const where = { businessModel };
  if (user.role !== 'ADMIN') where.agentId = user.id;
  if (propertyId) where.id = propertyId;
  const properties = await Property.findAll({
    where, order: [['name', 'ASC']], limit: 500,
    attributes: ['id', 'name', 'businessModel', 'agentId']
  });
  const propertyIds = properties.map((property) => property.id);
  if (!propertyIds.length) return {
    properties: [], summary: emptySummary(), trends: [], expensesByCategory: [],
    recentExpenses: [], bills: [], staff: [], rents: [], alerts: []
  };
  const dateRange = {};
  if (from) dateRange[Op.gte] = from;
  if (to) dateRange[Op.lte] = to;
  const appliesDate = Boolean(from || to);
  const expenseWhere = { propertyId: { [Op.in]: propertyIds }, reversedAt: { [Op.is]: null } };
  const billWhere = { propertyId: { [Op.in]: propertyIds }, reversedAt: { [Op.is]: null } };
  const staffWhere = { propertyId: { [Op.in]: propertyIds }, reversedAt: { [Op.is]: null } };
  if (appliesDate) {
    expenseWhere.expenseDate = dateRange;
    billWhere.billingMonth = {};
    if (from) billWhere.billingMonth[Op.gte] = from.slice(0, 7);
    if (to) billWhere.billingMonth[Op.lte] = to.slice(0, 7);
    staffWhere.dueDate = dateRange;
  }
  const [expenses, bills, staff, obligations, bookings, alerts] = await Promise.all([
    PropertyExpense.findAll({ where: expenseWhere, order: [['expenseDate', 'DESC']], limit: 100 }),
    UtilityBill.findAll({ where: billWhere, order: [['dueDate', 'ASC']], limit: 100 }),
    StaffObligation.findAll({ where: staffWhere, order: [['dueDate', 'ASC']], limit: 100 }),
    businessModel === 'contactUnlock'
      ? RentObligation.findAll({
        where: { propertyId: { [Op.in]: propertyIds }, ...(from || to ? {
          billingMonth: {
            ...(from ? { [Op.gte]: from.slice(0, 7) } : {}),
            ...(to ? { [Op.lte]: to.slice(0, 7) } : {})
          }
        } : {}) },
        order: [['dueDate', 'ASC']], limit: 100
      }) : Promise.resolve([]),
    businessModel === 'bookable'
      ? Booking.findAll({
        where: { propertyId: { [Op.in]: propertyIds }, status: { [Op.ne]: 'cancelled' } },
        include: [{ model: Property, as: 'property', attributes: ['id', 'name'] },
          { model: PaymentTransaction, as: 'transaction', required: false,
            attributes: ['id', 'amountTzs', 'status', 'verifiedAt'] }],
        order: [['createdAt', 'DESC']], limit: 500
      }) : Promise.resolve([]),
    FinancialAlert.findAll({
      where: { propertyId: { [Op.in]: propertyIds }, resolvedAt: { [Op.is]: null },
        ...(user.role === 'ADMIN' ? {} : { ownerId: user.id }) },
      include: [{ model: Property, as: 'property', attributes: ['id', 'name'] }],
      order: [['createdAt', 'DESC']], limit: 100
    })
  ]);
  if (user.role !== 'ADMIN') {
    await Promise.all(properties.map((property) => refreshPropertyAlerts(property, user.id)));
  }
  const paidBills = await Promise.all(bills.map((bill) => paidAmount('utilityBill', bill.id)));
  const paidStaff = await Promise.all(staff.map((item) => paidAmount('staffObligation', item.id)));
  const paidExpenses = await Promise.all(expenses.map((item) => paidAmount('propertyExpense', item.id)));
  const rentReceipts = await RentReceipt.findAll({
    where: obligations.length ? { obligationId: { [Op.in]: obligations.map((item) => item.id) },
      reversedAt: { [Op.is]: null } } : { id: '__none__' }
  });
  const cashPaymentWhere = {
    propertyId: { [Op.in]: propertyIds }, reversedAt: { [Op.is]: null }
  };
  if (appliesDate) cashPaymentWhere.paymentDate = dateRange;
  const cashPaid = await FinancialPayment.sum('amountTzs', { where: cashPaymentWhere }) || 0;
  const paidRents = new Map();
  for (const receipt of rentReceipts) {
    paidRents.set(receipt.obligationId, (paidRents.get(receipt.obligationId) || 0) + receipt.amountTzs);
  }
  const receiptDateRange = { reversedAt: { [Op.is]: null } };
  if (from || to) {
    receiptDateRange.paymentDate = {};
    if (from) receiptDateRange.paymentDate[Op.gte] = from;
    if (to) receiptDateRange.paymentDate[Op.lte] = to;
  }
  const collectedReceipts = businessModel === 'contactUnlock'
    ? await RentReceipt.findAll({
      where: receiptDateRange,
      include: [{
        model: RentObligation, as: 'obligation', required: true,
        where: { propertyId: { [Op.in]: propertyIds } },
        attributes: ['id', 'billingMonth']
      }]
    }) : [];
  const activeBookings = bookings.filter((booking) =>
    ['confirmed', 'completed'].includes(booking.status) &&
    booking.transaction?.status === 'succeeded' &&
    (!appliesDate ||
      dateOnly(booking.transaction.verifiedAt || booking.createdAt) >= (from || '0000-01-01') &&
      dateOnly(booking.transaction.verifiedAt || booking.createdAt) <= (to || '9999-12-31'))
  );
  const rentalExpected = obligations.reduce((sum, item) => sum + item.expectedTzs, 0);
  const rentalCollected = collectedReceipts.reduce((sum, receipt) => sum + receipt.amountTzs, 0);
  const bookingRevenue = activeBookings.reduce((sum, booking) => sum + booking.subtotalTzs, 0);
  const platformReceived = activeBookings.reduce((sum, booking) => sum + booking.transaction.amountTzs, 0);
  const rentOutstanding = obligations.reduce((sum, item) =>
    sum + Math.max(0, item.expectedTzs - (paidRents.get(item.id) || 0)), 0);
  const bookingOutstanding = businessModel === 'bookable'
    ? bookings.filter((booking) => booking.status === 'pending' &&
      (!appliesDate ||
        dateOnly(booking.createdAt) >= (from || '0000-01-01') &&
        dateOnly(booking.createdAt) <= (to || '9999-12-31')))
      .reduce((sum, booking) => sum + booking.totalTzs, 0) : 0;
  const expenseTotal = expenses.reduce((sum, item) => sum + item.amountTzs, 0) +
    bills.reduce((sum, item) => sum + item.amountTzs, 0) +
    staff.reduce((sum, item) => sum + item.amountTzs, 0);
  const revenue = businessModel === 'bookable' ? bookingRevenue : rentalExpected;
  const paidExpenseTotal = paidExpenses.reduce((a, b) => a + b, 0) +
    paidBills.reduce((a, b) => a + b, 0) + paidStaff.reduce((a, b) => a + b, 0);
  const summary = {
    expectedRentTzs: rentalExpected, rentCollectedTzs: rentalCollected,
    outstandingRentTzs: rentOutstanding, bookingRevenueTzs: bookingRevenue,
    platformPaymentsReceivedTzs: platformReceived, bookingPaymentsOutstandingTzs: bookingOutstanding,
    expenseTzs: expenseTotal, paidExpenseTzs: paidExpenseTotal,
    staffObligationsTzs: staff.reduce((sum, item) => sum + item.amountTzs, 0),
    staffPaidTzs: paidStaff.reduce((a, b) => a + b, 0),
    utilityBillsOutstandingTzs: bills.reduce((sum, bill, i) =>
      sum + Math.max(0, bill.amountTzs - paidBills[i]), 0),
    operatingProfitTzs: revenue - expenseTotal,
    cashFlowTzs: (businessModel === 'bookable' ? platformReceived : rentalCollected) - cashPaid,
    incomeBasis: businessModel === 'bookable'
      ? 'Confirmed/completed bookings with succeeded Haven Link payments; gross booking subtotal. Verified payment receipts are customer charges, not agent payouts.'
      : 'Rent expected is accrued income; collected rent is agent-reported offline receipts and is not verified by Haven Link.',
    profitBasis: 'Operating profit is recognized income less accrued operating expenses; it is not cash flow.',
    currency: 'TZS'
  };
  const rentRecords = await Promise.all(obligations.map(async (item) => {
    const row = { ...item.toJSON(), propertyName: properties.find((p) => p.id === item.propertyId)?.name };
    const paidTzs = paidRents.get(item.id) || 0;
    return { ...row, paidTzs, outstandingTzs: item.expectedTzs - paidTzs,
      status: item.expectedTzs === paidTzs ? 'paid'
        : item.dueDate < darEsSalaamDate() ? 'overdue' : paidTzs ? 'partiallyPaid' : 'pending' };
  }));
  const recentExpenses = expenses.map((item, index) => ({
    ...item.toJSON(), paidTzs: paidExpenses[index],
    propertyName: properties.find((p) => p.id === item.propertyId)?.name
  }));
  const billRecords = bills.map((item, index) => ({
    ...item.toJSON(), paidTzs: paidBills[index],
    status: obligationStatus(item.amountTzs, paidBills[index], item.dueDate),
    propertyName: properties.find((p) => p.id === item.propertyId)?.name
  }));
  const staffRecords = staff.map((item, index) => ({
    ...item.toJSON(), paidTzs: paidStaff[index],
    status: obligationStatus(item.amountTzs, paidStaff[index], item.dueDate),
    propertyName: properties.find((p) => p.id === item.propertyId)?.name
  }));
  const categories = new Map();
  for (const expense of expenses) categories.set(expense.category,
    (categories.get(expense.category) || 0) + expense.amountTzs);
  for (const bill of bills) categories.set(bill.category,
    (categories.get(bill.category) || 0) + bill.amountTzs);
  if (staff.length) categories.set('staff', staff.reduce((sum, item) => sum + item.amountTzs, 0));
  const monthKeys = new Set([
    ...obligations.map((item) => item.billingMonth),
    ...collectedReceipts.map((item) => dateOnly(item.paymentDate).slice(0, 7)),
    ...expenses.map((item) => item.expenseDate.slice(0, 7)),
    ...bills.map((item) => item.billingMonth),
    ...staff.map((item) => item.dueDate.slice(0, 7)),
    ...activeBookings.map((item) => item.transaction.verifiedAt
      ? dateOnly(item.transaction.verifiedAt).slice(0, 7)
      : item.createdAt.toISOString().slice(0, 7))
  ]);
  const trends = [...monthKeys].sort().map((month) => {
    const expectedTzs = obligations.filter((item) => item.billingMonth === month)
      .reduce((sum, item) => sum + item.expectedTzs, 0);
    const rentCollectedTzs = collectedReceipts.filter((item) =>
      dateOnly(item.paymentDate).slice(0, 7) === month
    ).reduce((sum, item) => sum + item.amountTzs, 0);
    const bookingTzs = activeBookings.filter((item) =>
      (item.transaction.verifiedAt
        ? dateOnly(item.transaction.verifiedAt).slice(0, 7)
        : item.createdAt.toISOString().slice(0, 7)) === month
    ).reduce((sum, item) => sum + item.subtotalTzs, 0);
    const bookingReceivedTzs = activeBookings.filter((item) =>
      (item.transaction.verifiedAt
        ? dateOnly(item.transaction.verifiedAt).slice(0, 7)
        : item.createdAt.toISOString().slice(0, 7)) === month
    ).reduce((sum, item) => sum + item.transaction.amountTzs, 0);
    const expenseTzs = expenses.filter((item) => item.expenseDate.slice(0, 7) === month)
      .reduce((sum, item) => sum + item.amountTzs, 0) +
      bills.filter((item) => item.billingMonth === month).reduce((sum, item) => sum + item.amountTzs, 0) +
      staff.filter((item) => item.dueDate.slice(0, 7) === month).reduce((sum, item) => sum + item.amountTzs, 0);
    const incomeTzs = businessModel === 'bookable' ? bookingTzs : expectedTzs;
    return {
      month, expectedTzs, collectedTzs: businessModel === 'bookable' ? bookingReceivedTzs : rentCollectedTzs,
      incomeTzs, expenseTzs, operatingProfitTzs: incomeTzs - expenseTzs
    };
  });
  return {
    properties: properties.map((property) => ({ id: property.id, name: property.name })),
    summary, trends,
    expensesByCategory: [...categories].map(([category, amountTzs]) => ({ category, amountTzs })),
    recentExpenses, bills: billRecords, staff: staffRecords, rents: rentRecords,
    alerts: user.role === 'ADMIN' ? alerts : await FinancialAlert.findAll({
      where: { ownerId: user.id, propertyId: { [Op.in]: propertyIds }, resolvedAt: { [Op.is]: null } },
      include: [{ model: Property, as: 'property', attributes: ['id', 'name'] }],
      order: [['createdAt', 'DESC']], limit: 100
    }),
    bookingRecords: activeBookings.slice(0, 50).map((booking) => ({
      id: booking.id, propertyId: booking.propertyId, propertyName: booking.property.name,
      date: booking.transaction.verifiedAt || booking.createdAt,
      revenueTzs: booking.subtotalTzs,
      platformPaymentTzs: booking.transaction.amountTzs,
      transactionStatus: booking.transaction.status,
      bookingStatus: booking.status
    }))
  };
}

function emptySummary() {
  return {
    expectedRentTzs: 0, rentCollectedTzs: 0, outstandingRentTzs: 0,
    bookingRevenueTzs: 0, platformPaymentsReceivedTzs: 0,
    bookingPaymentsOutstandingTzs: 0, expenseTzs: 0, paidExpenseTzs: 0,
    staffObligationsTzs: 0, staffPaidTzs: 0, utilityBillsOutstandingTzs: 0,
    operatingProfitTzs: 0, cashFlowTzs: 0, currency: 'TZS',
    incomeBasis: 'No eligible records in this period.',
    profitBasis: 'Operating profit is recognized income less accrued operating expenses; it is not cash flow.'
  };
}

async function adminOverview() {
  const [rentalAgents, stayAgents, properties, financialRecords, unresolvedAlerts,
    rentalIncomeRows, stayBookings, expenses, bills, staff] = await Promise.all([
    User.count({ where: { role: 'RENTAL_AGENT' } }),
    User.count({ where: { role: 'STAY_AGENT' } }),
    Property.findAll({ attributes: ['id', 'name', 'businessModel'], order: [['name', 'ASC']] }),
    Promise.all([RentObligation.count(), PropertyExpense.count(), UtilityBill.count(), StaffObligation.count()]),
    FinancialAlert.findAll({
      where: { resolvedAt: { [Op.is]: null } },
      include: [{ model: Property, as: 'property', attributes: ['id', 'name', 'businessModel'] }],
      order: [['createdAt', 'DESC']], limit: 100
    }),
    RentReceipt.findAll({ where: { reversedAt: { [Op.is]: null } },
      include: [{ model: RentObligation, as: 'obligation', include: [{ model: Property, as: 'property', attributes: ['businessModel'] }] }] }),
    Booking.findAll({
      where: { status: { [Op.in]: ['confirmed', 'completed'] } },
      include: [{ model: Property, as: 'property', attributes: ['businessModel'] },
        { model: PaymentTransaction, as: 'transaction', required: true,
          where: { status: 'succeeded' }, attributes: ['id', 'amountTzs', 'status'] }],
      order: [['createdAt', 'DESC']]
    }),
    PropertyExpense.findAll({ where: { reversedAt: { [Op.is]: null } } }),
    UtilityBill.findAll({ where: { reversedAt: { [Op.is]: null } } }),
    StaffObligation.findAll({ where: { reversedAt: { [Op.is]: null } } })
  ]);
  const rentalReportedTzs = rentalIncomeRows.reduce((sum, receipt) =>
    receipt.obligation?.property?.businessModel === 'contactUnlock' ? sum + receipt.amountTzs : sum, 0);
  const stayGrossBookingTzs = stayBookings.reduce((sum, booking) => sum + booking.subtotalTzs, 0);
  const platformPaymentsTzs = stayBookings.reduce((sum, booking) => sum + booking.transaction.amountTzs, 0);
  const expenseByCategory = new Map();
  for (const expense of expenses) expenseByCategory.set(expense.category,
    (expenseByCategory.get(expense.category) || 0) + expense.amountTzs);
  for (const bill of bills) expenseByCategory.set(bill.category,
    (expenseByCategory.get(bill.category) || 0) + bill.amountTzs);
  if (staff.length) expenseByCategory.set('staff',
    staff.reduce((sum, item) => sum + item.amountTzs, 0));
  const [duplicatePayments, excessRentReceipts, refundIssues, propertyWithRecords] =
    await Promise.all([
      sequelize.query(`
        SELECT propertyId, recordType, recordId, amountTzs, paymentDate, COUNT(*) AS count
        FROM FinancialPayments
        WHERE reversedAt IS NULL
        GROUP BY propertyId, recordType, recordId, amountTzs, paymentDate
        HAVING COUNT(*) > 1
        LIMIT 100
      `, { type: sequelize.QueryTypes.SELECT }),
      sequelize.query(`
        SELECT o.id AS recordId, o.propertyId, o.expectedTzs,
          SUM(r.amountTzs) AS receiptsTzs
        FROM RentObligations o
        JOIN RentReceipts r ON r.obligationId = o.id AND r.reversedAt IS NULL
        GROUP BY o.id
        HAVING SUM(r.amountTzs) > o.expectedTzs
        LIMIT 100
      `, { type: sequelize.QueryTypes.SELECT }),
      sequelize.query(`
        SELECT b.id AS bookingId, b.propertyId, b.status AS bookingStatus,
          t.status AS paymentStatus
        FROM Bookings b
        JOIN Properties p ON p.id = b.propertyId
        LEFT JOIN PaymentTransactions t ON t.id = b.paymentTransactionId
        WHERE p.businessModel = 'bookable' AND b.status IN ('confirmed', 'completed')
          AND (t.status IS NULL OR t.status = 'refunded')
        LIMIT 100
      `, { type: sequelize.QueryTypes.SELECT }),
      sequelize.query(`
        SELECT propertyId FROM RentObligations
        UNION SELECT propertyId FROM PropertyExpenses
        UNION SELECT propertyId FROM UtilityBills
        UNION SELECT propertyId FROM StaffObligations
      `, { type: sequelize.QueryTypes.SELECT })
    ]);
  const namesById = new Map(properties.map((property) => [property.id, property.name]));
  const performance = new Map(properties.map((property) => [property.id, {
    propertyId: property.id, propertyName: property.name,
    businessModel: property.businessModel, revenueTzs: 0, expenseTzs: 0
  }]));
  for (const receipt of rentalIncomeRows) {
    const row = performance.get(receipt.obligation?.propertyId);
    if (row && receipt.obligation?.property?.businessModel === 'contactUnlock') {
      row.revenueTzs += receipt.amountTzs;
    }
  }
  for (const booking of stayBookings) {
    const row = performance.get(booking.propertyId);
    if (row) row.revenueTzs += booking.subtotalTzs;
  }
  for (const expense of [...expenses, ...bills, ...staff]) {
    const row = performance.get(expense.propertyId);
    if (row) row.expenseTzs += expense.amountTzs;
  }
  const activityByMonth = new Map();
  for (const receipt of rentalIncomeRows) {
    if (receipt.obligation?.property?.businessModel !== 'contactUnlock') continue;
    const month = dateOnly(receipt.paymentDate).slice(0, 7);
    const row = activityByMonth.get(month) || { month, rentalReceiptsTzs: 0, stayBookingGrossTzs: 0 };
    row.rentalReceiptsTzs += receipt.amountTzs;
    activityByMonth.set(month, row);
  }
  for (const booking of stayBookings) {
    const month = dateOnly(booking.transaction.verifiedAt || booking.createdAt).slice(0, 7);
    const row = activityByMonth.get(month) || { month, rentalReceiptsTzs: 0, stayBookingGrossTzs: 0 };
    row.stayBookingGrossTzs += booking.subtotalTzs;
    activityByMonth.set(month, row);
  }
  const discrepancies = [
    ...duplicatePayments.map((item) => ({
      type: 'possibleDuplicatePayment', severity: 'warning',
      propertyId: item.propertyId, propertyName: namesById.get(item.propertyId) || 'Unknown property',
      recordType: item.recordType, recordId: item.recordId,
      description: `${item.count} matching payments of TZS ${item.amountTzs} are recorded for the same obligation and date.`
    })),
    ...excessRentReceipts.map((item) => ({
      type: 'rentOverpayment', severity: 'critical',
      propertyId: item.propertyId, propertyName: namesById.get(item.propertyId) || 'Unknown property',
      recordType: 'rentObligation', recordId: item.recordId,
      description: `Receipts total TZS ${item.receiptsTzs}, above expected rent of TZS ${item.expectedTzs}.`
    })),
    ...refundIssues.map((item) => ({
      type: item.paymentStatus === 'refunded' ? 'refundedBookingStillActive' : 'bookingPaymentMissing',
      severity: 'critical', propertyId: item.propertyId,
      propertyName: namesById.get(item.propertyId) || 'Unknown property',
      recordType: 'booking', recordId: item.bookingId,
      description: `Booking is ${item.bookingStatus} while its payment is ${item.paymentStatus || 'missing'}.`
    }))
  ];
  const alertSeverityCounts = await FinancialAlert.findAll({
    attributes: ['severity', [sequelize.fn('COUNT', sequelize.col('id')), 'count']],
    where: { resolvedAt: { [Op.is]: null } },
    group: ['severity'], raw: true
  });
  return {
    agentCounts: { rental: rentalAgents, stays: stayAgents },
    propertiesWithFinancialRecords: propertyWithRecords.length,
    totalProperties: properties.length, financialRecordCounts: financialRecords,
    agentReportedRentalReceiptsTzs: rentalReportedTzs,
    confirmedStayBookingGrossTzs: stayGrossBookingTzs,
    verifiedPlatformPaymentReceiptsTzs: platformPaymentsTzs,
    expensesByCategory: [...expenseByCategory].map(([category, amountTzs]) => ({ category, amountTzs })),
    propertyPerformance: [...performance.values()].map((item) => ({
      ...item, operatingProfitTzs: item.revenueTzs - item.expenseTzs
    })),
    financialActivityByMonth: [...activityByMonth.values()].sort((a, b) => a.month.localeCompare(b.month)),
    unresolvedAlertsBySeverity: alertSeverityCounts.map((item) => ({
      severity: item.severity, count: Number(item.count)
    })),
    unresolvedAlerts,
    financialRecordsRequireReview: discrepancies
  };
}

module.exports = {
  paidAmount, obligationStatus, serializeObligation, recordPayment, reversePayment,
  audit, refreshPropertyAlerts, getDashboard, adminOverview, TYPES
};
