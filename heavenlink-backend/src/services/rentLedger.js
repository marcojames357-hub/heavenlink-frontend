const { Op, Transaction } = require('sequelize');
const { sequelize, RentObligation, RentReceipt } = require('../models');

class RentLedgerError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function darEsSalaamDate(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Dar_es_Salaam', year: 'numeric', month: '2-digit', day: '2-digit'
  }).format(date);
}

function describeObligation(obligation, receipts, today = darEsSalaamDate()) {
  const active = receipts.filter((receipt) => !receipt.reversedAt);
  const paidTzs = active.reduce((sum, receipt) => sum + receipt.amountTzs, 0);
  const outstandingTzs = obligation.expectedTzs - paidTzs;
  return {
    ...obligation.toJSON(),
    paidTzs,
    outstandingTzs,
    status: outstandingTzs === 0 ? 'paid'
      : obligation.dueDate < today ? 'overdue'
        : paidTzs > 0 ? 'partiallyPaid' : 'pending',
    receipts: receipts.map((receipt) => ({
      ...receipt.toJSON(),
      source: 'manualOffline',
      platformVerified: false
    }))
  };
}

async function addReceipt(obligationId, actorId, input) {
  return sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
    const prior = await RentReceipt.findOne({
      where: { createdById: actorId, idempotencyKey: input.idempotencyKey }, transaction
    });
    if (prior) {
      if (prior.obligationId !== obligationId || prior.amountTzs !== input.amountTzs ||
          prior.paymentDate !== input.paymentDate || prior.reference !== input.reference) {
        throw new RentLedgerError(409, 'Idempotency key was already used for a different receipt');
      }
      return { receipt: prior, created: false };
    }

    const obligation = await RentObligation.findByPk(obligationId, { transaction });
    if (!obligation) throw new RentLedgerError(404, 'Rent obligation not found');
    const paidTzs = await RentReceipt.sum('amountTzs', {
      where: { obligationId, reversedAt: { [Op.is]: null } }, transaction
    }) || 0;
    if (input.amountTzs > obligation.expectedTzs - paidTzs) {
      throw new RentLedgerError(409, 'Receipt exceeds the outstanding rent');
    }
    const receipt = await RentReceipt.create({
      obligationId, createdById: actorId, ...input
    }, { transaction });
    return { receipt, created: true };
  });
}

async function reverseReceipt(receiptId, actorId, reason) {
  return sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
    const receipt = await RentReceipt.findByPk(receiptId, { transaction });
    if (!receipt) throw new RentLedgerError(404, 'Receipt not found');
    if (receipt.reversedAt) throw new RentLedgerError(409, 'Receipt is already reversed');
    await receipt.update({
      reversedAt: new Date(), reversedById: actorId, reversalReason: reason
    }, { transaction });
    return receipt;
  });
}

module.exports = { RentLedgerError, darEsSalaamDate, describeObligation, addReceipt, reverseReceipt };
