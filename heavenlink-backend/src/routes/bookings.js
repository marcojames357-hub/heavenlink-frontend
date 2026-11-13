const express = require('express');
const { body, validationResult } = require('express-validator');
const { Op, Transaction } = require('sequelize');
const { sequelize, Booking, BookingReceipt, Property, RoomType, RoomInventory, Room, RoomAvailabilityBlock, ApartmentAvailabilityBlock, User, BusinessConfiguration, Notification } = require('../models');
const { authenticateToken, requireRole } = require('../middleware/auth');
const paymentService = require('../services/paymentService');
const { notify } = require('../services/notify');
const { getBookingPayment, isVerifiedBookingPayment } = require('../services/bookingPayment');
const { unavailableRoomIds } = require('../services/roomAvailability');

const router = express.Router();

// Business configuration
const BOOKING_FEE_RATE = parseFloat(process.env.BOOKING_FEE_RATE) || 0.02;
const isWholeApartment = (property) =>
  property.businessModel === 'bookable' &&
  ['servicedApartment', 'shortStayApartment'].includes(property.category);
const isMultiRoomStay = (property) =>
  property.businessModel === 'bookable' &&
  ['hotel', 'motel', 'lodge'].includes(property.accommodationType || property.category);

// Returns a message when the stay breaks the host's capacity or night limits.
const apartmentRuleViolation = (property, nights, guestCount) => {
  if (property.maxGuests && Number(guestCount) > property.maxGuests) {
    return `This apartment sleeps up to ${property.maxGuests} guests`;
  }
  const rules = property.stayRules || {};
  if (rules.minNights && nights < rules.minNights) {
    return `Minimum stay is ${rules.minNights} nights`;
  }
  if (rules.maxNights && nights > rules.maxNights) {
    return `Maximum stay is ${rules.maxNights} nights`;
  }
  return null;
};

// Whole-apartment subtotal: Friday/Saturday nights use the optional weekend
// rate, and the optional cleaning fee is charged once per stay.
const apartmentSubtotal = (property, baseRate, checkInDate, checkOutDate, useBaseOnly) => {
  const rules = property.stayRules || {};
  const weekendRate = !useBaseOnly && rules.weekendPriceTzs > 0 ? rules.weekendPriceTzs : baseRate;
  let total = 0;
  for (let night = new Date(checkInDate); night < checkOutDate; night.setUTCDate(night.getUTCDate() + 1)) {
    const day = night.getUTCDay();
    total += day === 5 || day === 6 ? weekendRate : baseRate;
  }
  return total + (rules.cleaningFeeTzs > 0 ? rules.cleaningFeeTzs : 0);
};
const checkPropertyDuringReservation = async (property, transaction) => {
  const current = await Property.findByPk(property.id, { transaction });
  if (!current || !current.isPublic() || !current.available ||
      current.businessModel !== 'bookable' ||
      current.category !== property.category ||
      current.accommodationType !== property.accommodationType) {
    const error = new Error('The property changed while booking. Check availability again.');
    error.status = 409;
    throw error;
  }
};

const checkCategoryDuringReservation = async (selected, transaction) => {
  if (!selected) return;
  const current = await RoomType.findByPk(selected.id, { transaction });
  if (!current || current.listingId !== selected.listingId ||
      current.nightlyPriceTzs !== selected.nightlyPriceTzs ||
      current.capacity !== selected.capacity) {
    const error = new Error('The room category changed while booking. Check availability again.');
    error.status = 409;
    throw error;
  }
};

const apartmentHasConflict = async (propertyId, checkIn, checkOut, transaction) => {
  const startDay = checkIn.toISOString().slice(0, 10);
  const endDay = checkOut.toISOString().slice(0, 10);
  if (await ApartmentAvailabilityBlock.findOne({
    where: { propertyId, startDate: { [Op.lt]: endDay }, endDate: { [Op.gt]: startDay } },
    attributes: ['id'],
    transaction
  })) return true;
  return Boolean(await Booking.findOne({
    where: {
      propertyId,
      checkIn: { [Op.lt]: checkOut },
      checkOut: { [Op.gt]: checkIn },
      [Op.or]: [
        { status: { [Op.in]: ['confirmed', 'completed'] } },
        { status: 'pending', holdExpiresAt: { [Op.gt]: new Date() } }
      ]
    },
    attributes: ['id'],
    transaction
  }));
};

const findBookingReplay = async (request, transaction) => {
  const booking = await Booking.findOne({
    where: { requestKey: request.body.requestKey },
    transaction
  });
  if (!booking) return null;

  const { propertyId, checkIn, checkOut, guestName, guestPhone, guestCount = 1, roomTypeId } = request.body;
  if (booking.customerId !== request.user.id ||
      booking.propertyId !== propertyId ||
      new Date(booking.checkIn).getTime() !== new Date(checkIn).getTime() ||
      new Date(booking.checkOut).getTime() !== new Date(checkOut).getTime() ||
      booking.guestName !== guestName ||
      (booking.guestPhone || null) !== (guestPhone || null) ||
      booking.guestCount !== Number(guestCount) ||
      (booking.roomTypeId || null) !== (roomTypeId || null)) {
    const error = new Error('Booking request key is already used for a different request');
    error.status = 409;
    throw error;
  }
  return booking;
};

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

    const existingBooking = await findBookingReplay(req);
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
    if (!property.available) {
      return res.status(409).json({ error: 'This property is not currently available' });
    }
    if (isMultiRoomStay(property) && !roomTypeId) {
      return res.status(400).json({ error: 'Choose a room category for this property' });
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
    if (isWholeApartment(property)) {
      const violation = apartmentRuleViolation(property, nights, guestCount);
      if (violation) return res.status(400).json({ error: violation });
    }

    let selectedRoomType = null;
    let physicalInventory = false;

    // Check room availability if room type specified.
    if (roomTypeId) {
      selectedRoomType = await RoomType.findOne({
        where: { id: roomTypeId, listingId: propertyId }
      });

      if (!selectedRoomType) {
        return res.status(404).json({ error: 'Room type not found' });
      }
      if (guestCount > selectedRoomType.capacity) {
        return res.status(400).json({ error: 'Guest count exceeds this room category capacity' });
      }

      const physicalRooms = await Room.count({
        where: {
          propertyId,
          roomTypeId
        }
      });
      if (isMultiRoomStay(property) && physicalRooms === 0) {
        return res.status(409).json({ error: 'No physical rooms are assigned to this category' });
      }
      physicalInventory = !isWholeApartment(property) && physicalRooms > 0;

      // Check availability for each night
      const dates = [];
      let currentDate = new Date(checkInDate);
      while (currentDate < checkOutDate) {
        dates.push(currentDate.toISOString().split('T')[0]);
        currentDate.setDate(currentDate.getDate() + 1);
      }

      for (const date of physicalInventory || isWholeApartment(property) ? [] : dates) {
        const inventory = await RoomInventory.findOne({
          where: { roomTypeId, date }
        });

        const available = inventory 
          ? inventory.availableFor(selectedRoomType)
          : selectedRoomType.totalRooms;

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
      ? selectedRoomType.nightlyPriceTzs
      : property.priceTzs;

    const subtotal = isWholeApartment(property)
      ? apartmentSubtotal(property, pricePerNight, checkInDate, checkOutDate, Boolean(roomTypeId))
      : pricePerNight * nights;
    const businessConfiguration = await BusinessConfiguration.findByPk(1);
    const feeRate = businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE;
    const fee = Math.round(subtotal * feeRate);
    const total = subtotal + fee;

    const bookingData = {
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
    };
    let booking;
    let replayed = false;
    if (isWholeApartment(property)) {
      try {
        booking = await sequelize.transaction({
          type: Transaction.TYPES.IMMEDIATE
        }, async (transaction) => {
          await checkPropertyDuringReservation(property, transaction);
          await checkCategoryDuringReservation(selectedRoomType, transaction);
          const replay = await findBookingReplay(req, transaction);
          if (replay) {
            replayed = true;
            return replay;
          }
          if (await apartmentHasConflict(propertyId, checkInDate, checkOutDate, transaction)) {
            const error = new Error('Apartment is not available for selected dates');
            error.status = 409;
            throw error;
          }
          return Booking.create({
            ...bookingData,
            holdExpiresAt: new Date(Date.now() + 15 * 60 * 1000)
          }, { transaction });
        });
      } catch (error) {
        if (error.status === 409) {
          return res.status(409).json({ error: error.message });
        }
        throw error;
      }
    } else if (physicalInventory) {
      try {
        booking = await sequelize.transaction({
          type: Transaction.TYPES.IMMEDIATE
        }, async (transaction) => {
          await checkPropertyDuringReservation(property, transaction);
          await checkCategoryDuringReservation(selectedRoomType, transaction);
          const replay = await findBookingReplay(req, transaction);
          if (replay) {
            replayed = true;
            return replay;
          }
          const rooms = await Room.findAll({
            where: { propertyId, roomTypeId, status: 'active' },
            order: [['roomNumber', 'ASC']],
            transaction
          });
          const occupiedRoomIds = await unavailableRoomIds(
            rooms.map((room) => room.id), checkInDate, checkOutDate, { transaction }
          );
          const availableRoom = rooms.find((room) => !occupiedRoomIds.has(room.id));
          if (!availableRoom) {
            const error = new Error('Room not available for selected dates');
            error.status = 409;
            throw error;
          }
          return Booking.create({
            ...bookingData,
            assignedRoomId: availableRoom.id,
            holdExpiresAt: new Date(Date.now() + 15 * 60 * 1000)
          }, { transaction });
        });
      } catch (error) {
        if (error.status === 409) {
          return res.status(409).json({ error: error.message });
        }
        throw error;
      }
    } else {
      booking = await Booking.create(bookingData);
    }
    if (replayed) {
      return res.json({ message: 'Booking request already exists', booking });
    }
    const assignedRoom = booking.assignedRoomId
      ? await Room.findByPk(booking.assignedRoomId, { attributes: ['roomNumber'] })
      : null;

    res.status(201).json({
      message: 'Booking created successfully',
      booking: {
        id: booking.id,
        propertyId: booking.propertyId,
        roomTypeId: booking.roomTypeId,
        assignedRoomId: booking.assignedRoomId,
        assignedRoomNumber: assignedRoom?.roomNumber ?? null,
        holdExpiresAt: booking.holdExpiresAt,
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
    if (error.status === 409) {
      return res.status(409).json({ error: error.message });
    }
    if (error.name === 'SequelizeUniqueConstraintError') {
      try {
        const replay = await findBookingReplay(req);
        if (replay) {
          return res.json({ message: 'Booking request already exists', booking: replay });
        }
      } catch (replayError) {
        if (replayError.status === 409) {
          return res.status(409).json({ error: replayError.message });
        }
        console.error('Find booking replay error:', replayError);
        return res.status(500).json({ error: 'Failed to create booking' });
      }
    }
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
        },
        { model: RoomType, as: 'roomType', attributes: ['id', 'name'] },
        { model: Room, as: 'assignedRoom', attributes: ['id', 'roomNumber'] }
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
router.get('/:id/receipt', authenticateToken, async (req, res) => {
  try {
    const booking = await Booking.findByPk(req.params.id, { attributes: ['id', 'customerId', 'status'] });
    if (!booking || (booking.customerId !== req.user.id && req.user.role !== 'ADMIN')) {
      return res.status(404).json({ error: 'Receipt not found' });
    }
    const receipt = await BookingReceipt.findOne({ where: { bookingId: booking.id } });
    if (!receipt) return res.status(404).json({ error: 'No receipt has been issued for this booking' });
    res.json({
      receipt: {
        id: receipt.id, receiptNumber: receipt.receiptNumber, issuedAt: receipt.issuedAt,
        ...receipt.snapshot
      }
    });
  } catch (error) {
    console.error('Get receipt error:', error);
    res.status(500).json({ error: 'Failed to load receipt' });
  }
});

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
        },
        { model: RoomType, as: 'roomType', attributes: ['id', 'name'] },
        { model: Room, as: 'assignedRoom', attributes: ['id', 'roomNumber'] }
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
      return res.status(403).json({
        error: 'Bookings can only be confirmed through verified payment processing'
      });
    }
    if (status === 'completed' && new Date(booking.checkIn) > new Date()) {
      return res.status(400).json({ error: 'A stay cannot be checked out before check-in' });
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

    await booking.update(status === 'completed' ? { status, checkedOutAt: new Date() } : { status });

    if (status === 'completed' &&
        isVerifiedBookingPayment(booking, await getBookingPayment(booking))) {
      await notify(booking.customerId, 'CUSTOMER', `How was your stay at ${property.name}?`,
        'Write a review, or report a problem privately. You can do either or both.',
        '/account/reviews', 'Write a Review', {
          type: 'REVIEW_INVITATION', category: 'review', propertyId: property.id,
          bookingId: booking.id, dedupeKey: `review-invite:${booking.id}`, sms: false
        });
    }

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

    await booking.update({ status: 'cancelled', holdExpiresAt: null });

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
    if (!property || !property.isPublic() || property.businessModel !== 'bookable') {
      return res.status(404).json({ error: 'Property not found' });
    }

    const checkInDate = new Date(checkIn);
    const checkOutDate = new Date(checkOut);

    if (Number.isNaN(checkInDate.getTime()) || Number.isNaN(checkOutDate.getTime()) ||
        checkOutDate <= checkInDate) {
      return res.status(400).json({ error: 'Check-out date must be after check-in date' });
    }

    if (isWholeApartment(property)) {
      let apartmentRate = property.priceTzs;
      if (roomTypeId) {
        const roomType = await RoomType.findOne({ where: { id: roomTypeId, listingId: propertyId } });
        if (!roomType) return res.status(404).json({ error: 'Room type not found' });
        if (req.query.guestCount && Number(req.query.guestCount) > roomType.capacity) {
          return res.status(400).json({ error: 'Guest count exceeds this room category capacity' });
        }
        apartmentRate = roomType.nightlyPriceTzs;
      }
      const available = property.available &&
        !await apartmentHasConflict(propertyId, checkInDate, checkOutDate);
      const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
      const violation = apartmentRuleViolation(
        property, nights, Math.max(1, Number(req.query.guestCount) || 1)
      );
      if (violation) return res.status(400).json({ error: violation });
      const subtotal = apartmentSubtotal(
        property, apartmentRate, checkInDate, checkOutDate, Boolean(roomTypeId)
      );
      const businessConfiguration = await BusinessConfiguration.findByPk(1);
      const fee = Math.round(subtotal * (businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE));
      return res.json({
        available, availableRooms: available ? 1 : 0, pricePerNight: apartmentRate,
        nights, subtotal, fee, total: subtotal + fee, currency: 'TZS'
      });
    }

    let available = true;
    let availableRooms = 0;
    let pricePerNight = property.priceTzs;

    if (!roomTypeId) {
      const guestCount = Math.max(1, Number(req.query.guestCount) || 1);
      const roomTypes = await RoomType.findAll({
        where: { listingId: propertyId, capacity: { [Op.gte]: guestCount } },
        order: [['nightlyPriceTzs', 'ASC']]
      });

      if (roomTypes.length > 0) {
        const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
        let totalAvailable = 0;
        let lowestAvailableRate = null;
        for (const roomType of roomTypes) {
          const rooms = await Room.findAll({
            where: { propertyId, roomTypeId: roomType.id, status: 'active' },
            attributes: ['id']
          });
          let categoryAvailable = isMultiRoomStay(property) ? 0 : roomType.totalRooms;
          if (rooms.length > 0) {
            const roomIds = rooms.map((room) => room.id);
            const occupied = await unavailableRoomIds(roomIds, checkInDate, checkOutDate);
            categoryAvailable = rooms.filter((room) => !occupied.has(room.id)).length;
          } else if (!isMultiRoomStay(property)) {
            for (
              let date = new Date(checkInDate);
              date < checkOutDate;
              date.setDate(date.getDate() + 1)
            ) {
              const inventory = await RoomInventory.findOne({
                where: { roomTypeId: roomType.id, date: date.toISOString().slice(0, 10) }
              });
              categoryAvailable = Math.min(
                categoryAvailable,
                inventory ? inventory.availableFor(roomType) : roomType.totalRooms
              );
            }
          }
          if (categoryAvailable > 0) {
            totalAvailable += categoryAvailable;
            lowestAvailableRate = lowestAvailableRate === null
              ? roomType.nightlyPriceTzs
              : Math.min(lowestAvailableRate, roomType.nightlyPriceTzs);
          }
        }

        availableRooms = totalAvailable;
        available = totalAvailable > 0;
        pricePerNight = lowestAvailableRate ?? 0;
        const subtotal = pricePerNight * nights;
        const businessConfiguration = await BusinessConfiguration.findByPk(1);
        const feeRate = businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE;
        const fee = Math.round(subtotal * feeRate);
        return res.json({
          available,
          availableRooms,
          pricePerNight,
          nights,
          subtotal,
          fee,
          total: subtotal + fee,
          currency: 'TZS'
        });
      }

      const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
      if (isMultiRoomStay(property)) {
        return res.json({
          available: false, availableRooms: 0, pricePerNight: 0,
          nights, subtotal: 0, fee: 0, total: 0, currency: 'TZS'
        });
      }
      const subtotal = property.priceTzs * nights;
      const businessConfiguration = await BusinessConfiguration.findByPk(1);
      const feeRate = businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE;
      const fee = Math.round(subtotal * feeRate);
      return res.json({
        available: property.available,
        availableRooms: property.available ? 1 : 0,
        pricePerNight: property.priceTzs,
        nights,
        subtotal,
        fee,
        total: subtotal + fee,
        currency: 'TZS'
      });
    }

    if (roomTypeId) {
      const roomType = await RoomType.findOne({
        where: { id: roomTypeId, listingId: propertyId }
      });

      if (!roomType) {
        return res.status(404).json({ error: 'Room type not found' });
      }

      pricePerNight = roomType.nightlyPriceTzs;
      if (req.query.guestCount && Number(req.query.guestCount) > roomType.capacity) {
        return res.status(400).json({ error: 'Guest count exceeds this room category capacity' });
      }

      const physicalRooms = await Room.findAll({
        where: { propertyId, roomTypeId },
        attributes: ['id']
      });
      if (isMultiRoomStay(property) && physicalRooms.length === 0) {
        const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
        const subtotal = pricePerNight * nights;
        const businessConfiguration = await BusinessConfiguration.findByPk(1);
        const fee = Math.round(subtotal * (businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE));
        return res.json({
          available: false, availableRooms: 0, pricePerNight,
          nights, subtotal, fee, total: subtotal + fee, currency: 'TZS'
        });
      }
      if (physicalRooms.length > 0) {
        const activeRooms = await Room.findAll({
          where: {
            id: { [Op.in]: physicalRooms.map((room) => room.id) },
            status: 'active'
          },
          attributes: ['id']
        });
        const occupied = await unavailableRoomIds(
          activeRooms.map((room) => room.id), checkInDate, checkOutDate
        );
        availableRooms = activeRooms.filter((room) => !occupied.has(room.id)).length;
        available = availableRooms > 0;
        const nights = Math.ceil((checkOutDate - checkInDate) / (1000 * 60 * 60 * 24));
        const subtotal = pricePerNight * nights;
        const businessConfiguration = await BusinessConfiguration.findByPk(1);
        const feeRate = businessConfiguration?.bookingFeeRate ?? BOOKING_FEE_RATE;
        const fee = Math.round(subtotal * feeRate);
        return res.json({
          available,
          availableRooms,
          pricePerNight,
          nights,
          subtotal,
          fee,
          total: subtotal + fee,
          currency: 'TZS'
        });
      }

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
