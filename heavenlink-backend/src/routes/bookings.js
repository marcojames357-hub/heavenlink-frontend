const express = require('express');
const { body, validationResult } = require('express-validator');
const { Booking, Property, RoomType, RoomInventory, PaymentTransaction, User, BusinessConfiguration } = require('../models');
const { authenticateToken, requireRole } = require('../middleware/auth');
const paymentService = require('../services/paymentService');

const router = express.Router();

// Business configuration
const BOOKING_FEE_RATE = parseFloat(process.env.BOOKING_FEE_RATE) || 0.02;

// Create booking
router.post('/', authenticateToken, requireRole('CUSTOMER', 'ADMIN'), [
  body('propertyId').isUUID(),
  body('requestKey').isString().isLength({ min: 1, max: 200 }),
  body('checkIn').isISO8601(),
  body('checkOut').isISO8601(),
  body('guestName').trim().isLength({ min: 2, max: 100 }),
  body('guestPhone').optional().matches(/^\+255\d{9}$/),
  body('guestCount').optional().isInt({ min: 1, max: 20 }),
  body('roomTypeId').optional().isUUID()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { propertyId, requestKey, checkIn, checkOut, guestName, guestPhone, guestCount = 1, roomTypeId } = req.body;

    const existingBooking = await Booking.findOne({
      where: { customerId: req.user.id, requestKey }
    });
    if (existingBooking) {
      return res.json({ message: 'Booking request already exists', booking: existingBooking });
    }

    const property = await Property.findByPk(propertyId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.businessModel !== 'bookable') {
      return res.status(400).json({ error: 'This property does not support bookings' });
    }

    if (!property.isPublic()) {
      return res.status(403).json({ error: 'Property is not available for booking' });
    }

    // Validate dates
    const checkInDate = new Date(checkIn);
    const checkOutDate = new Date(checkOut);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (checkInDate < today) {
      return res.status(400).json({ error: 'Check-in date cannot be in the past' });
    }

    if (checkOutDate <= checkInDate) {
      return res.status(400).json({ error: 'Check-out date must be after check-in date' });
    }

    // Calculate nights
    const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
    if (nights < 1) {
      return res.status(400).json({ error: 'Minimum stay is 1 night' });
    }

    // Check room availability if room type specified
    if (roomTypeId) {
      const roomType = await RoomType.findOne({
        where: { id: roomTypeId, listingId: propertyId }
      });

      if (!roomType) {
        return res.status(404).json({ error: 'Room type not found' });
      }

      // Check availability for each night
      const dates = [];
      let currentDate = new Date(checkInDate);
      while (currentDate < checkOutDate) {
        dates.push(currentDate.toISOString().split('T')[0]);
        currentDate.setDate(currentDate.getDate() + 1);
      }

      for (const date of dates) {
        const inventory = await RoomInventory.findOne({
          where: { roomTypeId, date }
        });

        const available = inventory
          ? inventory.availableFor(roomType)
          : roomType.totalRooms;

        if (available < 1) {
          return res.status(400).json({
            error: 'Room not available for selected dates',
            date
          });
        }
      }
    }

    // Calculate pricing
    const pricePerNight = roomTypeId
      ? (await RoomType.findByPk(roomTypeId)).nightlyPriceTzs
      : property.priceTzs;

    const subtotal = pricePerNight * nights;
    const businessConfiguration = await BusinessConfiguration.findByPk(1);
    const feeRate = businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE;
    const fee = Math.round(subtotal * feeRate);
    const total = subtotal + fee;

    // Create booking with pending status
    const booking = await Booking.create({
      propertyId,
      requestKey,
      customerId: req.user.id,
      checkIn: checkInDate,
      checkOut: checkOutDate,
      guestName,
      guestPhone,
      guestCount,
      subtotalTzs: subtotal,
      feeTzs: fee,
      totalTzs: total,
      status: 'pending',
      roomTypeId
    });

    res.status(201).json({
      message: 'Booking created successfully',
      booking: {
        id: booking.id,
        propertyId: booking.propertyId,
        checkIn: booking.checkIn,
        checkOut: booking.checkOut,
        guestName: booking.guestName,
        guestCount: booking.guestCount,
        subtotalTzs: booking.subtotalTzs,
        feeTzs: booking.feeTzs,
        totalTzs: booking.totalTzs,
        status: booking.status,
        nights
      }
    });
  } catch (error) {
    console.error('Create booking error:', error);
    res.status(500).json({ error: 'Failed to create booking' });
  }
});

// Get user's bookings
router.get('/', authenticateToken, async (req, res) => {
  try {
    const { status } = req.query;

    const where = { customerId: req.user.id };
    if (status) where.status = status;

    const bookings = await Booking.findAll({
      where,
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood', 'imageUrl', 'priceTzs']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ bookings });
  } catch (error) {
    console.error('Get bookings error:', error);
    res.status(500).json({ error: 'Failed to fetch bookings' });
  }
});

// Get single booking
router.get('/:id', authenticateToken, async (req, res) => {
  try {
    const booking = await Booking.findByPk(req.params.id, {
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood', 'imageUrl', 'priceTzs', 'businessModel']
        },
        {
          model: User,
          as: 'customer',
          attributes: ['id', 'fullName', 'email', 'phone']
        }
      ]
    });

    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    // Check ownership or admin
    if (booking.customerId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this booking' });
    }

    res.json({ booking });
  } catch (error) {
    console.error('Get booking error:', error);
    res.status(500).json({ error: 'Failed to fetch booking' });
  }
});

// Update booking status
router.patch('/:id/status', authenticateToken, [
  body('status').isIn(['pending', 'confirmed', 'completed', 'cancelled'])
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const booking = await Booking.findByPk(req.params.id);
    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    const { status } = req.body;
    const property = await Property.findByPk(booking.propertyId);
    const isAdmin = req.user.role === 'ADMIN';
    const isCustomer = booking.customerId === req.user.id;
    const isStayAgent = property?.agentId === req.user.id &&
      req.user.hasCapability('accommodationBooking');
    if (!isAdmin && !isCustomer && !isStayAgent) {
      return res.status(403).json({ error: 'You do not have permission to update this booking' });
    }
    if (!isAdmin && isCustomer && status !== 'cancelled') {
      return res.status(403).json({ error: 'Customers may only cancel their own bookings' });
    }
    if (status === 'confirmed') {
      const transaction = booking.paymentTransactionId
        ? await PaymentTransaction.findByPk(booking.paymentTransactionId)
        : null;
      if (!transaction || transaction.status !== 'succeeded' || !transaction.verifiedAt) {
        return res.status(403).json({ error: 'A verified payment is required to confirm this booking' });
      }
    }

    const validTransitions = {
      'pending': ['confirmed', 'cancelled'],
      'confirmed': ['completed', 'cancelled'],
      'completed': [],
      'cancelled': []
    };

    if (!validTransitions[booking.status].includes(status)) {
      return res.status(400).json({
        error: 'Invalid status transition',
        currentStatus: booking.status,
        requestedStatus: status
      });
    }

    await booking.update({ status });

    res.json({ message: 'Booking status updated successfully', booking });
  } catch (error) {
    console.error('Update booking status error:', error);
    res.status(500).json({ error: 'Failed to update booking status' });
  }
});

// Cancel booking
router.post('/:id/cancel', authenticateToken, async (req, res) => {
  try {
    const booking = await Booking.findByPk(req.params.id);
    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    const property = await Property.findByPk(booking.propertyId);
    const isCustomer = booking.customerId === req.user.id;
    const isStayAgent = property?.agentId === req.user.id &&
      req.user.hasCapability('accommodationBooking');
    if (!isCustomer && !isStayAgent && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to cancel this booking' });
    }

    if (booking.status === 'cancelled' || booking.status === 'completed') {
      return res.status(400).json({ error: 'Booking cannot be cancelled' });
    }

    await booking.update({ status: 'cancelled' });

    // Update room inventory
    if (booking.roomTypeId) {
      const dates = [];
      let currentDate = new Date(booking.checkIn);
      const checkOutDate = new Date(booking.checkOut);
      while (currentDate < checkOutDate) {
        dates.push(currentDate.toISOString().split('T')[0]);
        currentDate.setDate(currentDate.getDate() + 1);
      }

      for (const date of dates) {
        const inventory = await RoomInventory.findOne({
          where: { roomTypeId: booking.roomTypeId, date }
        });

        if (inventory) {
          await inventory.update({
            booked: Math.max(0, inventory.booked - 1)
          });
        }
      }
    }

    res.json({ message: 'Booking cancelled successfully' });
  } catch (error) {
    console.error('Cancel booking error:', error);
    res.status(500).json({ error: 'Failed to cancel booking' });
  }
});

// Check availability
router.get('/availability/check', async (req, res) => {
  try {
    const { propertyId, checkIn, checkOut, roomTypeId } = req.query;

    if (!propertyId || !checkIn || !checkOut) {
      return res.status(400).json({ error: 'propertyId, checkIn, and checkOut are required' });
    }

    const property = await Property.findByPk(propertyId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    const checkInDate = new Date(checkIn);
    const checkOutDate = new Date(checkOut);

    if (checkOutDate <= checkInDate) {
      return res.status(400).json({ error: 'Check-out date must be after check-in date' });
    }

    let available = true;
    let availableRooms = 0;
    let pricePerNight = property.priceTzs;

    if (roomTypeId) {
      const roomType = await RoomType.findOne({
        where: { id: roomTypeId, listingId: propertyId }
      });

      if (!roomType) {
        return res.status(404).json({ error: 'Room type not found' });
      }

      pricePerNight = roomType.nightlyPriceTzs;

      // Check availability for each night
      const dates = [];
      let currentDate = new Date(checkInDate);
      while (currentDate < checkOutDate) {
        dates.push(currentDate.toISOString().split('T')[0]);
        currentDate.setDate(currentDate.getDate() + 1);
      }

      let minAvailable = Infinity;
      for (const date of dates) {
        const inventory = await RoomInventory.findOne({
          where: { roomTypeId, date }
        });

        const available = inventory
          ? inventory.availableFor(roomType)
          : roomType.totalRooms;

        minAvailable = Math.min(minAvailable, available);
      }

      availableRooms = minAvailable;
      available = availableRooms > 0;
    }

    const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
    const subtotal = pricePerNight * nights;
    const fee = Math.round(subtotal * BOOKING_FEE_RATE);
    const total = subtotal + fee;

    res.json({
      available,
      availableRooms,
      pricePerNight,
      nights,
      subtotal,
      fee,
      total,
      currency: 'TZS'
    });
  } catch (error) {
    console.error('Check availability error:', error);
    res.status(500).json({ error: 'Failed to check availability' });
  }
});

module.exports = router;
