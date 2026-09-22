const express = require('express');
const { body, validationResult } = require('express-validator');
const { PaymentTransaction, UnlockRecord, Booking, Property, User, BusinessConfiguration } = require('../models');
const { authenticateToken } = require('../middleware/auth');
const paymentService = require('../services/paymentService');

const router = express.Router();

// Business configuration
const DEFAULT_UNLOCK_FEE = parseInt(process.env.DEFAULT_UNLOCK_FEE_TZS) || 5000;
const BOOKING_FEE_RATE = parseFloat(process.env.BOOKING_FEE_RATE) || 0.02;

router.get('/config', async (req, res) => {
  try {
    const stored = await BusinessConfiguration.findByPk(1);
    res.json({
      config: {
        unlockFeeTzs: stored?.unlockFeeTzs ?? DEFAULT_UNLOCK_FEE,
        bookingFeeRate: stored?.bookingFeeRate ?? BOOKING_FEE_RATE,
        currency: 'TZS',
        paymentMethods: paymentService.getAvailableMethods()
      }
    });
  } catch (error) {
    console.error('Get public business configuration error:', error.message);
    res.status(500).json({ error: 'Failed to fetch configuration' });
  }
});

// Create payment transaction
router.post('/transactions', authenticateToken, [
  body('purpose').isIn(['rentalContactUnlock', 'accommodationBooking']),
  body('amountTzs').isInt({ min: 1 }),
  body('methodId').isString(),
  body('listingId').optional().isUUID(),
  body('bookingId').optional().isUUID()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { purpose, methodId, listingId, bookingId } = req.body;

    // Validate purpose-specific requirements
    let amountTzs;
    if (purpose === 'rentalContactUnlock') {
      if (!listingId) {
        return res.status(400).json({ error: 'listingId is required for rental contact unlock' });
      }
      const property = await Property.findByPk(listingId);
      if (!property || property.businessModel !== 'contactUnlock' || !property.isPublic()) {
        return res.status(404).json({ error: 'Rental listing not found' });
      }
      const existingUnlock = await UnlockRecord.findOne({
        where: { customerId: req.user.id, listingId, status: 'active' }
      });
      if (existingUnlock) {
        return res.status(409).json({ error: 'Contact is already unlocked' });
      }
      const config = await BusinessConfiguration.findByPk(1);
      amountTzs = config?.unlockFeeTzs ?? DEFAULT_UNLOCK_FEE;
    }

    if (purpose === 'accommodationBooking' && !bookingId) {
      return res.status(400).json({ error: 'bookingId is required for accommodation booking' });
    }
    if (purpose === 'accommodationBooking') {
      const booking = await Booking.findOne({
        where: { id: bookingId, customerId: req.user.id, status: 'pending' }
      });
      if (!booking) return res.status(404).json({ error: 'Pending booking not found' });
      amountTzs = booking.totalTzs;
    }

    // Check if payment service is configured
    if (!paymentService.isConfigured()) {
      return res.status(503).json({
        error: 'Payment service not configured',
        message: 'Payment processing is not available. Please contact support.'
      });
    }

    // Generate idempotency key
    const idempotencyKey = req.headers['idempotency-key'];
    if (!idempotencyKey || idempotencyKey.length > 200) {
      return res.status(400).json({ error: 'A valid idempotency-key header is required' });
    }
    const previousTransaction = await PaymentTransaction.findOne({ where: { idempotencyKey } });
    if (previousTransaction) {
      if (previousTransaction.customerId !== req.user.id) {
        return res.status(409).json({ error: 'Idempotency key already used' });
      }
      return res.json({ transaction: previousTransaction });
    }

    const transaction = await paymentService.createTransaction(
      purpose,
      amountTzs,
      methodId,
      req.user.id,
      listingId,
      bookingId,
      idempotencyKey
    );

    res.status(201).json({
      message: 'Payment transaction created',
      transaction: {
        id: transaction.id,
        reference: transaction.reference,
        purpose: transaction.purpose,
        amountTzs: transaction.amountTzs,
        currency: transaction.currency,
        methodId: transaction.methodId,
        status: transaction.status,
        createdAt: transaction.createdAt,
        providerResponse: transaction.providerResponse
      }
    });
  } catch (error) {
    console.error('Create payment error:', error);
    res.status(500).json({ error: 'Failed to create payment transaction' });
  }
});

// Get payment transaction status
router.get('/transactions/:id', authenticateToken, async (req, res) => {
  try {
    const transaction = await PaymentTransaction.findByPk(req.params.id);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Verify ownership
    if (transaction.customerId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this transaction' });
    }

    res.json({
      transaction: {
        id: transaction.id,
        reference: transaction.reference,
        purpose: transaction.purpose,
        amountTzs: transaction.amountTzs,
        currency: transaction.currency,
        methodId: transaction.methodId,
        status: transaction.status,
        createdAt: transaction.createdAt,
        verifiedAt: transaction.verifiedAt,
        failureMessage: transaction.failureMessage
      }
    });
  } catch (error) {
    console.error('Get transaction error:', error);
    res.status(500).json({ error: 'Failed to fetch transaction' });
  }
});

// Verify payment and process unlock/booking
router.post('/transactions/:id/verify', authenticateToken, async (req, res) => {
  try {
    if (!paymentService.isConfigured()) {
      return res.status(503).json({ error: 'Payment verification is not configured' });
    }
    const transaction = await PaymentTransaction.findByPk(req.params.id);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Verify ownership
    if (transaction.customerId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to verify this transaction' });
    }

    // Verify payment with provider
    const verifiedTransaction = await paymentService.verifyTransaction(transaction.id);

    // Process based on purpose
    if (verifiedTransaction.purpose === 'rentalContactUnlock' && verifiedTransaction.status === 'succeeded') {
      // Create unlock record
      const existingUnlock = await UnlockRecord.findOne({
        where: {
          customerId: req.user.id,
          listingId: transaction.listingId
        }
      });

      if (!existingUnlock) {
        await UnlockRecord.create({
          customerId: req.user.id,
          listingId: transaction.listingId,
          paymentTransactionId: transaction.id,
          status: 'active',
          confirmedAt: new Date(),
          amountTzs: transaction.amountTzs
        });
      } else if (existingUnlock.status !== 'active') {
        await existingUnlock.update({
          status: 'active',
          confirmedAt: new Date(),
          paymentTransactionId: transaction.id
        });
      }
    } else if (verifiedTransaction.purpose === 'accommodationBooking' && verifiedTransaction.status === 'succeeded') {
      // Update booking status
      const booking = await Booking.findOne({
        where: { paymentTransactionId: transaction.id }
      });

      if (booking) {
        await booking.update({
          status: 'confirmed',
          paymentTransactionId: transaction.id
        });
      }
    }

    res.json({
      message: 'Payment verified successfully',
      transaction: {
        id: verifiedTransaction.id,
        reference: verifiedTransaction.reference,
        purpose: verifiedTransaction.purpose,
        amountTzs: verifiedTransaction.amountTzs,
        currency: verifiedTransaction.currency,
        methodId: verifiedTransaction.methodId,
        status: verifiedTransaction.status,
        createdAt: verifiedTransaction.createdAt,
        verifiedAt: verifiedTransaction.verifiedAt
      }
    });
  } catch (error) {
    console.error('Verify payment error:', error);
    res.status(500).json({ error: 'Failed to verify payment' });
  }
});

// Get user's payment history
router.get('/history', authenticateToken, async (req, res) => {
  try {
    const transactions = await PaymentTransaction.findAll({
      where: { customerId: req.user.id },
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ transactions });
  } catch (error) {
    console.error('Get payment history error:', error);
    res.status(500).json({ error: 'Failed to fetch payment history' });
  }
});

// Get unlock records for user
router.get('/unlocks', authenticateToken, async (req, res) => {
  try {
    const unlocks = await UnlockRecord.findAll({
      where: { customerId: req.user.id },
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood', 'priceTzs', 'imageUrl']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ unlocks });
  } catch (error) {
    console.error('Get unlocks error:', error);
    res.status(500).json({ error: 'Failed to fetch unlock records' });
  }
});

// Get single unlock record
router.get('/unlocks/:id', authenticateToken, async (req, res) => {
  try {
    const unlock = await UnlockRecord.findByPk(req.params.id, {
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood', 'priceTzs', 'imageUrl']
        }
      ]
    });

    if (!unlock) {
      return res.status(404).json({ error: 'Unlock record not found' });
    }

    // Verify ownership
    if (unlock.customerId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this unlock' });
    }

    res.json({ unlock });
  } catch (error) {
    console.error('Get unlock error:', error);
    res.status(500).json({ error: 'Failed to fetch unlock record' });
  }
});

// Webhook endpoints for payment providers
router.post('/mpesa/callback', (req, res) => {
  res.status(503).json({ error: 'M-Pesa callbacks are not configured' });
});

module.exports = router;
