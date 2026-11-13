const express = require('express');
const rateLimit = require('express-rate-limit');
const { body, validationResult } = require('express-validator');
const { Op, Transaction } = require('sequelize');
const {
  Property, Booking, RoomType, RoomInventory, CheckInPolicy, GuestMessage,
  Notification, UnlockRecord, User, AgentProfile, Floor, Room,
  RoomAvailabilityBlock, ApartmentAvailabilityBlock, AdminAuditEvent, PaymentTransaction, WalkInReservation,
  WalkInRoomSegment, RentalMessage, sequelize
} = require('../models');
const { authenticateToken, requireRole, requireCapability, requireVerifiedPhone } = require('../middleware/auth');
const { notify } = require('../services/notify');
const { getBookingPayment, isVerifiedBookingPayment } = require('../services/bookingPayment');
const { unavailableRoomIds } = require('../services/roomAvailability');
const { hasWorkspace } = require('../services/workspaces');

const router = express.Router();

const isMultiRoomProperty = (property) =>
  property?.businessModel === 'bookable' &&
  ['hotel', 'motel', 'lodge'].includes(
    property.accommodationType || property.category
  );

const canManageProperty = (property, user) =>
  property && (property.agentId === user.id || user.role === 'ADMIN');

const recheckInventoryProperty = async (property, user, transaction) => {
  const current = await Property.findByPk(property.id, { transaction });
  if (!current || !canManageProperty(current, user) ||
      current.businessModel !== property.businessModel ||
      isMultiRoomProperty(current) !== isMultiRoomProperty(property)) {
    const error = new Error('Property inventory or permissions changed. Refresh and try again.');
    error.status = 409;
    throw error;
  }
};

const messageLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  keyGenerator: (req) => req.user.id,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many messages. Please try again later.' }
});
const messageFollowUpDays = process.env.STAY_MESSAGE_FOLLOW_UP_DAYS === undefined
  ? 14
  : Number(process.env.STAY_MESSAGE_FOLLOW_UP_DAYS);
if (!Number.isInteger(messageFollowUpDays) || messageFollowUpDays < 1 || messageFollowUpDays > 365) {
  throw new Error('STAY_MESSAGE_FOLLOW_UP_DAYS must be an integer from 1 to 365');
}
const MESSAGE_FOLLOW_UP_MS = messageFollowUpDays * 24 * 60 * 60 * 1000;

const validRentalUnlock = (unlock, customerId, listingId) => {
  const payment = unlock?.transaction;
  return Boolean(
    unlock &&
    unlock.status === 'active' &&
    unlock.customerId === customerId &&
    unlock.listingId === listingId &&
    payment &&
    payment.purpose === 'rentalContactUnlock' &&
    payment.status === 'succeeded' &&
    payment.verifiedAt &&
    payment.customerId === customerId &&
    payment.listingId === listingId &&
    payment.amountTzs === unlock.amountTzs
  );
};

const rentalPropertySummary = (property) => ({
  id: property.id,
  name: property.name,
  city: property.city,
  neighborhood: property.neighborhood,
  imageUrl: property.imageUrl
});

const rentalMessageAccess = async (listingId, customerId, user) => {
  const property = await Property.findByPk(listingId, {
    attributes: ['id', 'name', 'city', 'neighborhood', 'imageUrl', 'agentId', 'businessModel']
  });
  if (!property || property.businessModel !== 'contactUnlock') return null;

  const isCustomer = user.role === 'CUSTOMER' && customerId === user.id;
  const isAgent = property.agentId === user.id && user.hasCapability('rentalProperty');
  if (!isCustomer && !isAgent) return null;

  const unlock = await UnlockRecord.findOne({
    where: { listingId, customerId, status: 'active' },
    include: [{ model: PaymentTransaction, as: 'transaction' }]
  });
  if (!validRentalUnlock(unlock, customerId, listingId)) return null;
  return { property, isAgent };
};

const messageAccess = async (booking, user, sending) => {
  const property = await Property.findByPk(booking.propertyId);
  if (!property || property.businessModel !== 'bookable') return null;

  const isCustomer = user.role === 'CUSTOMER' && booking.customerId === user.id;
  const isAgent = property.agentId === user.id && user.hasCapability('accommodationBooking');
  if (!isCustomer && !isAgent) return null;
  if (!['confirmed', 'completed', 'cancelled'].includes(booking.status)) return null;

  const payment = await getBookingPayment(booking);
  if (!isVerifiedBookingPayment(booking, payment, sending ? ['succeeded'] : ['succeeded', 'refunded'])) return null;

  if (sending && booking.status === 'cancelled') return null;
  if (sending && booking.status === 'completed') {
    const checkout = booking.checkedOutAt && new Date(booking.checkedOutAt).getTime();
    if (!checkout || checkout > Date.now() ||
        Date.now() - checkout > MESSAGE_FOLLOW_UP_MS) return null;
  }
  return { property, isAgent };
};

// Get agent's listings
  router.get('/listings', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), async (req, res) => {
  try {
    const { businessModel, status } = req.query;
    
    const where = { agentId: req.user.id };
    if (businessModel) where.businessModel = businessModel;
    if (status) where.listingStatus = status;

    const listings = await Property.findAll({
      where,
      order: [['createdAt', 'DESC']]
    });

    res.json({ listings });
  } catch (error) {
    console.error('Get agent listings error:', error);
    res.status(500).json({ error: 'Failed to fetch listings' });
  }
});

// Get agent's bookings (for accommodation agents)
router.get('/bookings', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const { status } = req.query;
    
    // Get all property IDs owned by this agent
    const agentProperties = await Property.findAll({
      where: { 
        agentId: req.user.id,
        businessModel: 'bookable'
      },
      attributes: ['id']
    });

    const propertyIds = agentProperties.map(p => p.id);

    const where = { propertyId: propertyIds };
    if (status) where.status = status;

    const bookings = await Booking.findAll({
      where,
      include: [
        {
          model: Property,
          as: 'property',
          attributes: [
            'id', 'name', 'city', 'neighborhood', 'priceTzs', 'category',
            'imageUrl', 'imageUrls', 'rating', 'reviewCount', 'bedrooms',
            'bathrooms', 'amenities', 'description', 'available', 'furnished',
            'parking', 'water', 'electricity', 'security', 'managerName',
            'agentId'
          ]
        },
        { model: RoomType, as: 'roomType', attributes: ['id', 'name'] },
        { model: Room, as: 'assignedRoom', attributes: ['id', 'roomNumber'] }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ bookings });
  } catch (error) {
    console.error('Get agent bookings error:', error);
    res.status(500).json({ error: 'Failed to fetch bookings' });
  }
});

// Get agent's unlock activity (for rental agents)
router.get('/unlock-activity', authenticateToken, requireRole('RENTAL_AGENT', 'ADMIN'), async (req, res) => {
  try {
    // Get all property IDs owned by this agent
    const agentProperties = await Property.findAll({
      where: { 
        agentId: req.user.id,
        businessModel: 'contactUnlock'
      },
      attributes: ['id', 'name']
    });

    const propertyIds = agentProperties.map(p => p.id);

    const unlocks = await UnlockRecord.findAll({
      where: { listingId: propertyIds },
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ unlocks });
  } catch (error) {
    console.error('Get unlock activity error:', error);
    res.status(500).json({ error: 'Failed to fetch unlock activity' });
  }
});

// Get agent's notifications
router.get('/notifications', authenticateToken, async (req, res) => {
  try {
    const notifications = await Notification.findAll({
      where: { 
        userId: req.user.id,
        [Op.or]: [
          { audience: null },
          { audience: req.user.role }
        ]
      },
      order: [['createdAt', 'DESC']]
    });

    res.json({ notifications });
  } catch (error) {
    console.error('Get notifications error:', error);
    res.status(500).json({ error: 'Failed to fetch notifications' });
  }
});

// Mark notifications as read
router.put('/notifications/read', authenticateToken, async (req, res) => {
  try {
    await Notification.update(
      { isRead: true },
      { where: { userId: req.user.id, isRead: false } }
    );

    res.json({ message: 'Notifications marked as read' });
  } catch (error) {
    console.error('Mark notifications read error:', error);
    res.status(500).json({ error: 'Failed to mark notifications as read' });
  }
});

const isApartmentProperty = (property) =>
  property?.businessModel === 'bookable' &&
  ['servicedApartment', 'shortStayApartment'].includes(
    property.accommodationType || property.category
  );

const apartmentBlockGuard = async (req, res, next) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isApartmentProperty(property)) {
      return res.status(404).json({ error: 'Apartment not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to manage this apartment' });
    }
    if (!(await hasWorkspace(req.user, 'APARTMENT'))) {
      return res.status(403).json({ error: 'The Apartment Stays workspace is not active for this account' });
    }
    req.apartment = property;
    next();
  } catch (error) {
    console.error('Apartment guard error:', error);
    res.status(500).json({ error: 'Failed to check apartment access' });
  }
};

router.get('/apartments/:listingId/blocks', authenticateToken, requireCapability('accommodationBooking'), apartmentBlockGuard, async (req, res) => {
  const blocks = await ApartmentAvailabilityBlock.findAll({
    where: { propertyId: req.apartment.id },
    order: [['startDate', 'ASC']]
  });
  res.json({ blocks });
});

router.post('/apartments/:listingId/blocks', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, apartmentBlockGuard, async (req, res) => {
  try {
    const { startDate, endDate, reason } = req.body;
    const isDateOnly = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
      new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
    if (!isDateOnly(startDate) || !isDateOnly(endDate) || endDate <= startDate ||
        typeof reason !== 'string' || reason.trim().length < 2 || reason.trim().length > 500) {
      return res.status(400).json({ error: 'Provide valid dates and a reason of 2-500 characters' });
    }
    const block = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      const from = new Date(`${startDate}T00:00:00Z`);
      const until = new Date(`${endDate}T00:00:00Z`);
      const clash = await Booking.findOne({
        where: {
          propertyId: req.apartment.id, checkIn: { [Op.lt]: until }, checkOut: { [Op.gt]: from },
          [Op.or]: [
            { status: { [Op.in]: ['confirmed', 'completed'] } },
            { status: 'pending', holdExpiresAt: { [Op.gt]: new Date() } }
          ]
        },
        attributes: ['id'], transaction
      });
      if (clash) {
        const error = new Error('These dates overlap a reservation or an active checkout hold');
        error.status = 409;
        throw error;
      }
      const created = await ApartmentAvailabilityBlock.create({
        propertyId: req.apartment.id, startDate, endDate, reason: reason.trim()
      }, { transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'APARTMENT_AVAILABILITY_BLOCKED', entityType: 'Property',
        entityId: req.apartment.id, metadata: { blockId: created.id, startDate, endDate }, ipAddress: req.ip
      }, { transaction });
      return created;
    });
    res.status(201).json({ block });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Create apartment block error:', error);
    res.status(500).json({ error: 'Failed to block apartment dates' });
  }
});

router.delete('/apartments/:listingId/blocks/:blockId', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, apartmentBlockGuard, async (req, res) => {
  try {
    const block = await ApartmentAvailabilityBlock.findOne({
      where: { id: req.params.blockId, propertyId: req.apartment.id }
    });
    if (!block) return res.status(404).json({ error: 'Availability block not found' });
    await block.destroy();
    await AdminAuditEvent.create({
      actorId: req.user.id, action: 'APARTMENT_AVAILABILITY_UNBLOCKED', entityType: 'Property',
      entityId: req.apartment.id, metadata: { blockId: block.id }, ipAddress: req.ip
    });
    res.json({ message: 'Availability block removed' });
  } catch (error) {
    console.error('Remove apartment block error:', error);
    res.status(500).json({ error: 'Failed to remove availability block' });
  }
});

router.get('/rooms/:listingId/calendar', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) return res.status(404).json({ error: 'Multi-room accommodation not found' });
    if (!canManageProperty(property, req.user)) return res.status(403).json({ error: 'You do not have permission to view this inventory' });
    const { start, end } = req.query;
    const validDate = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
      !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) &&
      new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
    if (!validDate(start) || !validDate(end)) return res.status(400).json({ error: 'Provide valid start and end dates' });
    const from = new Date(`${start}T00:00:00Z`);
    const until = new Date(`${end}T00:00:00Z`);
    if (until <= from || until - from > 93 * 86400000) {
      return res.status(400).json({ error: 'Choose a date range of up to 93 days; end is exclusive' });
    }
    const rooms = await Room.findAll({
      where: { propertyId: property.id },
      include: [
        { model: Floor, as: 'floor', attributes: ['label'] },
        { model: RoomType, as: 'roomType', attributes: ['name'] }
      ],
      order: [['roomNumber', 'ASC']]
    });
    const ids = rooms.map((room) => room.id);
    const now = new Date();
    const [bookings, walkInSegments, blocks] = await Promise.all([
      Booking.findAll({
        where: {
          assignedRoomId: { [Op.in]: ids }, checkIn: { [Op.lt]: until }, checkOut: { [Op.gt]: from },
          [Op.or]: [{ status: 'confirmed' }, { status: 'pending', holdExpiresAt: { [Op.gt]: now } }]
        },
        attributes: ['id', 'assignedRoomId', 'checkIn', 'checkOut', 'status', 'guestName', 'holdExpiresAt']
      }),
      WalkInRoomSegment.findAll({
        where: {
          roomId: { [Op.in]: ids },
          startAt: { [Op.lt]: until },
          endAt: { [Op.gt]: from }
        },
        attributes: ['id', 'roomId', 'walkInReservationId', 'startAt', 'endAt'],
        include: [{
          model: WalkInReservation, as: 'reservation',
          where: { status: { [Op.in]: ['reserved', 'checkedIn'] } },
          attributes: ['status', 'guestName', 'checkOut'], required: true
        }]
      }),
      RoomAvailabilityBlock.findAll({
        where: { roomId: { [Op.in]: ids }, startDate: { [Op.lt]: end }, endDate: { [Op.gt]: start } },
        attributes: ['id', 'roomId', 'startDate', 'endDate', 'reason']
      })
    ]);
    const result = rooms.map((room) => ({
      id: room.id, roomNumber: room.roomNumber, status: room.status,
      floor: room.floor?.label || null, category: room.roomType?.name || null,
      occupancy: walkInSegments.some((segment) =>
        segment.roomId === room.id &&
        segment.reservation.status === 'checkedIn' &&
        segment.startAt <= now && segment.endAt > now
      ) ? 'checkedIn' : 'vacant',
      events: [
        ...bookings.filter((booking) => booking.assignedRoomId === room.id).map((booking) => ({
          id: booking.id, kind: booking.status === 'pending' ? 'hold' : 'online',
          start: booking.checkIn, end: booking.checkOut, guestName: booking.guestName
        })),
        ...walkInSegments.filter((segment) => segment.roomId === room.id).map((segment) => ({
          id: segment.walkInReservationId, kind: 'walkIn', start: segment.startAt, end: segment.endAt,
          guestName: segment.reservation.guestName,
          overdue: segment.reservation.status === 'checkedIn' && segment.reservation.checkOut <= now
        })),
        ...blocks.filter((block) => block.roomId === room.id).map((block) => ({
          id: block.id, kind: 'blocked', start: block.startDate, end: block.endDate, reason: block.reason
        }))
      ].sort((a, b) => new Date(a.start) - new Date(b.start))
    }));
    res.json({ start, end, rooms: result });
  } catch (error) {
    console.error('Get room calendar error:', error);
    res.status(500).json({ error: 'Failed to fetch room calendar' });
  }
});

router.get('/rooms/:listingId', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) {
      return res.status(404).json({ error: 'Multi-room accommodation not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to view this inventory' });
    }
    const rooms = await Room.findAll({
      where: { propertyId: property.id },
      include: [
        { model: Floor, as: 'floor', attributes: ['id', 'label', 'sortOrder'] },
        { model: RoomType, as: 'roomType', attributes: ['id', 'name', 'nightlyPriceTzs'] },
        { model: RoomAvailabilityBlock, as: 'availabilityBlocks' }
      ],
      order: [['roomNumber', 'ASC']]
    });
    res.json({
      rooms,
      totalRooms: rooms.length,
      assignedRooms: rooms.filter((room) => room.roomTypeId).length
    });
  } catch (error) {
    console.error('Get physical rooms error:', error);
    res.status(500).json({ error: 'Failed to fetch room inventory' });
  }
});

router.post('/rooms/:listingId/manual', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, [
  body('roomNumbers').isArray({ min: 1, max: 500 }),
  body('roomNumbers.*').isString().trim().isLength({ min: 1, max: 40 }).matches(/^[\p{L}\p{N}][\p{L}\p{N} ._-]*$/u)
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Provide 1-500 valid room identifiers', details: errors.array() });
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) return res.status(404).json({ error: 'Multi-room accommodation not found' });
    if (!canManageProperty(property, req.user)) return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    const numbers = req.body.roomNumbers;
    if (new Set(numbers.map((value) => value.toLocaleLowerCase('en-US'))).size !== numbers.length) {
      return res.status(400).json({ error: 'Room identifiers must be unique within the property' });
    }
    const created = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await recheckInventoryProperty(property, req.user, transaction);
      const existing = await Room.findAll({ where: { propertyId: property.id }, attributes: ['roomNumber'], transaction });
      const existingNumbers = new Set(existing.map((room) => room.roomNumber.toLocaleLowerCase('en-US')));
      if (numbers.some((number) => existingNumbers.has(number.toLocaleLowerCase('en-US')))) {
        const error = new Error('Room identifiers must be unique within the property');
        error.status = 409;
        throw error;
      }
      const rooms = await Room.bulkCreate(numbers.map((roomNumber) => ({
        propertyId: property.id, roomNumber, floorId: null
      })), { transaction, validate: true });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'ROOMS_MANUALLY_ADDED', entityType: 'Property',
        entityId: property.id, metadata: { roomIds: rooms.map((room) => room.id) }, ipAddress: req.ip
      }, { transaction });
      return rooms;
    });
    res.status(201).json({ rooms: created });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    if (error.name === 'SequelizeUniqueConstraintError') return res.status(409).json({ error: 'Room identifiers must be unique within the property' });
    console.error('Add physical rooms error:', error);
    res.status(500).json({ error: 'Failed to add physical rooms' });
  }
});

router.patch('/rooms/:listingId/:roomId', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, [
  body('roomNumber').isString().trim().isLength({ min: 1, max: 40 }).matches(/^[\p{L}\p{N}][\p{L}\p{N} ._-]*$/u)
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Provide a valid room identifier', details: errors.array() });
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) return res.status(404).json({ error: 'Multi-room accommodation not found' });
    if (!canManageProperty(property, req.user)) return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    const room = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      const current = await Room.findOne({ where: { id: req.params.roomId, propertyId: property.id }, transaction });
      if (!current) {
        const error = new Error('Room not found');
        error.status = 404;
        throw error;
      }
      const others = await Room.findAll({ where: { propertyId: property.id, id: { [Op.ne]: current.id } }, attributes: ['roomNumber'], transaction });
      if (others.some((item) => item.roomNumber.toLocaleLowerCase('en-US') === req.body.roomNumber.toLocaleLowerCase('en-US'))) {
        const error = new Error('Room identifier is already in use');
        error.status = 409;
        throw error;
      }
      const previous = current.roomNumber;
      await current.update({ roomNumber: req.body.roomNumber }, { transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'ROOM_IDENTIFIER_CHANGED', entityType: 'Room', entityId: current.id,
        metadata: { propertyId: property.id, previous, roomNumber: current.roomNumber }, ipAddress: req.ip
      }, { transaction });
      return current;
    });
    res.json({ room });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    if (error.name === 'SequelizeUniqueConstraintError') return res.status(409).json({ error: 'Room identifier is already in use' });
    console.error('Update room identifier error:', error);
    res.status(500).json({ error: 'Failed to update room identifier' });
  }
});

router.post('/rooms/:listingId/:roomId/blocks', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) {
      return res.status(404).json({ error: 'Multi-room accommodation not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    }
    const { startDate, endDate, reason } = req.body;
    const isDateOnly = (value) => {
      if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        return false;
      }
      const date = new Date(`${value}T00:00:00Z`);
      return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
    };
    if (!isDateOnly(startDate) || !isDateOnly(endDate) ||
        endDate <= startDate || typeof reason !== 'string' ||
        reason.trim().length < 2 || reason.trim().length > 500) {
      return res.status(400).json({ error: 'Provide valid dates and a reason of 2-500 characters' });
    }
    const room = await Room.findOne({
      where: { id: req.params.roomId, propertyId: property.id }
    });
    if (!room) return res.status(404).json({ error: 'Room not found' });

    const block = await sequelize.transaction({
      type: Transaction.TYPES.IMMEDIATE
    }, async (transaction) => {
      const unavailable = await unavailableRoomIds(
        [room.id], new Date(`${startDate}T00:00:00Z`),
        new Date(`${endDate}T00:00:00Z`), { transaction }
      );
      if (unavailable.has(room.id)) {
        const error = new Error('Room dates overlap a reservation, block or active checkout hold');
        error.status = 409;
        throw error;
      }
      const created = await RoomAvailabilityBlock.create({
        roomId: room.id,
        startDate,
        endDate,
        reason: reason.trim()
      }, { transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id,
        action: 'ROOM_AVAILABILITY_BLOCKED',
        entityType: 'Room',
        entityId: room.id,
        metadata: { propertyId: property.id, blockId: created.id, startDate, endDate },
        ipAddress: req.ip
      }, { transaction });
      return created;
    });
    res.status(201).json({ block });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Create room availability block error:', error);
    res.status(500).json({ error: 'Failed to block room dates' });
  }
});

router.delete('/rooms/:listingId/:roomId/blocks/:blockId', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) {
      return res.status(404).json({ error: 'Multi-room accommodation not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    }
    const room = await Room.findOne({
      where: { id: req.params.roomId, propertyId: property.id }
    });
    if (!room) return res.status(404).json({ error: 'Room not found' });
    const block = await RoomAvailabilityBlock.findOne({
      where: { id: req.params.blockId, roomId: room.id }
    });
    if (!block) return res.status(404).json({ error: 'Availability block not found' });
    await sequelize.transaction(async (transaction) => {
      await block.destroy({ transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id,
        action: 'ROOM_AVAILABILITY_UNBLOCKED',
        entityType: 'Room',
        entityId: room.id,
        metadata: { propertyId: property.id, blockId: block.id },
        ipAddress: req.ip
      }, { transaction });
    });
    res.json({ message: 'Room availability block removed' });
  } catch (error) {
    console.error('Remove room availability block error:', error);
    res.status(500).json({ error: 'Failed to remove availability block' });
  }
});

router.post('/rooms/:listingId/generate', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!isMultiRoomProperty(property)) {
      return res.status(404).json({ error: 'Multi-room accommodation not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    }
    const { floors } = req.body;
    if (!Array.isArray(floors) || floors.length < 1 || floors.length > 50) {
      return res.status(400).json({ error: 'Provide between 1 and 50 floors' });
    }
    let totalRooms = 0;
    const normalizedFloors = [];
    for (const [index, floor] of floors.entries()) {
      if (!floor || typeof floor.label !== 'string' || floor.label.trim().length < 1 ||
          !Number.isInteger(floor.roomCount) || floor.roomCount < 1 || floor.roomCount > 500) {
        return res.status(400).json({ error: 'Each floor needs a label and 1-500 rooms' });
      }
      if (floor.roomNumbers !== undefined &&
          (!Array.isArray(floor.roomNumbers) || floor.roomNumbers.length !== floor.roomCount ||
           floor.roomNumbers.some((number) => typeof number !== 'string' && !Number.isInteger(number)))) {
        return res.status(400).json({ error: 'Custom room numbers must match each floor room count' });
      }
      const startNumber = floor.startNumber === undefined
        ? (floors.length === 1 ? 1 : (index + 1) * 100 + 1)
        : floor.startNumber;
      if (!Array.isArray(floor.roomNumbers) && !Number.isInteger(startNumber)) {
        return res.status(400).json({ error: 'Floor startNumber must be a whole number' });
      }
      totalRooms += floor.roomCount;
      normalizedFloors.push({
        label: floor.label.trim(),
        sortOrder: index,
        startNumber,
        roomCount: floor.roomCount,
        roomNumbers: floor.roomNumbers?.map((number) => String(number).trim())
      });
    }
    if (totalRooms > 5000) {
      return res.status(400).json({ error: 'A property cannot generate more than 5,000 rooms at once' });
    }
    const allNumbers = normalizedFloors.flatMap((floor) =>
      floor.roomNumbers || Array.from(
        { length: floor.roomCount },
        (_, index) => String(floor.startNumber + index)
      )
    );
    if (allNumbers.some((number) => number.length > 40 ||
        !/^[\p{L}\p{N}][\p{L}\p{N} ._-]*$/u.test(number)) ||
        new Set(allNumbers.map((number) => number.toLocaleLowerCase('en-US'))).size !== allNumbers.length) {
      return res.status(400).json({ error: 'Room identifiers must be valid and unique within the property' });
    }

    const created = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await recheckInventoryProperty(property, req.user, transaction);
      const existingCount = await Room.count({
        where: { propertyId: property.id },
        transaction
      });
      if (existingCount > 0) {
        const error = new Error('Rooms already exist for this property');
        error.status = 409;
        throw error;
      }
      const createdFloors = await Floor.bulkCreate(
        normalizedFloors.map(({ label, sortOrder }) => ({
          propertyId: property.id,
          label,
          sortOrder
        })),
        { returning: true, transaction }
      );
      const roomRecords = normalizedFloors.flatMap((floor, index) =>
        (floor.roomNumbers || Array.from(
          { length: floor.roomCount },
          (_, roomIndex) => String(floor.startNumber + roomIndex)
        )).map((roomNumber) => ({
          propertyId: property.id,
          floorId: createdFloors[index].id,
          roomNumber
        }))
      );
      await Room.bulkCreate(roomRecords, { transaction, validate: true });
      await AdminAuditEvent.create({
        actorId: req.user.id,
        action: 'ROOM_INVENTORY_GENERATED',
        entityType: 'Property',
        entityId: property.id,
        metadata: { totalRooms, floorCount: createdFloors.length },
        ipAddress: req.ip
      }, { transaction });
      return { floors: createdFloors.length, rooms: totalRooms };
    });
    res.status(201).json({ message: 'Room inventory generated', ...created });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    if (error.name === 'SequelizeUniqueConstraintError') {
      return res.status(400).json({ error: 'Room numbers must be unique within the property' });
    }
    console.error('Generate room inventory error:', error);
    res.status(500).json({ error: 'Failed to generate room inventory' });
  }
});

router.post('/rooms/assign', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, [
  body('listingId').isUUID(),
  body('roomTypeId').isUUID(),
  body('roomIds').isArray({ min: 1, max: 500 }),
  body('roomIds.*').isUUID()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }
    const property = await Property.findByPk(req.body.listingId);
    if (!isMultiRoomProperty(property)) {
      return res.status(404).json({ error: 'Multi-room accommodation not found' });
    }
    if (!canManageProperty(property, req.user)) {
      return res.status(403).json({ error: 'You do not have permission to assign rooms' });
    }
    const roomType = await RoomType.findOne({
      where: { id: req.body.roomTypeId, listingId: property.id }
    });
    if (!roomType) return res.status(404).json({ error: 'Room category not found' });
    const roomIds = [...new Set(req.body.roomIds)];
    if (roomIds.length !== req.body.roomIds.length) {
      return res.status(400).json({ error: 'Room selection contains duplicates' });
    }
    await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await roomType.reload({ transaction });
      const rooms = await Room.findAll({
        where: { id: roomIds, propertyId: property.id },
        transaction
      });
      if (rooms.length !== roomIds.length) {
        const error = new Error('Every selected room must belong to this property');
        error.status = 400;
        throw error;
      }
      const assignedToCategory = await Room.count({
        where: { propertyId: property.id, roomTypeId: roomType.id },
        transaction
      });
      const alreadyInSelection = rooms.filter((room) => room.roomTypeId === roomType.id).length;
      if (assignedToCategory - alreadyInSelection + roomIds.length > roomType.totalRooms) {
        const error = new Error('This assignment exceeds the room count planned for the category');
        error.status = 400;
        error.plannedRooms = roomType.totalRooms;
        throw error;
      }
      const occupied = await Booking.count({
        where: {
          assignedRoomId: roomIds,
          checkOut: { [Op.gt]: new Date() },
          [Op.or]: [
            { status: 'confirmed' },
            { status: 'pending', holdExpiresAt: { [Op.gt]: new Date() } }
          ]
        },
        transaction
      });
      const walkInOccupied = await WalkInReservation.count({
        where: {
          roomId: roomIds,
          [Op.or]: [
            { status: 'reserved', checkOut: { [Op.gt]: new Date() } },
            { status: 'checkedIn' }
          ]
        },
        transaction
      });
      if (occupied > 0 || walkInOccupied > 0) {
        const error = new Error('Rooms with active stays cannot be reassigned');
        error.status = 409;
        throw error;
      }
      await Room.update(
        { roomTypeId: roomType.id },
        { where: { id: roomIds, propertyId: property.id }, transaction }
      );
      await AdminAuditEvent.create({
        actorId: req.user.id,
        action: 'ROOM_CATEGORY_ASSIGNED',
        entityType: 'RoomType',
        entityId: roomType.id,
        metadata: { propertyId: property.id, roomIds },
        ipAddress: req.ip
      }, { transaction });
    });
    res.json({ message: 'Room category assigned', assignedCount: roomIds.length });
  } catch (error) {
    if (error.status) {
      const response = { error: error.message };
      if (error.plannedRooms !== undefined) response.plannedRooms = error.plannedRooms;
      return res.status(error.status).json(response);
    }
    console.error('Assign room category error:', error);
    res.status(500).json({ error: 'Failed to assign room category' });
  }
});

// Room Type Management (for accommodation agents)
router.get('/room-types/:listingId', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this property' });
    }

    const roomTypes = await RoomType.findAll({
      where: { listingId: req.params.listingId },
      order: [['createdAt', 'DESC']]
    });

    res.json({ roomTypes });
  } catch (error) {
    console.error('Get room types error:', error);
    res.status(500).json({ error: 'Failed to fetch room types' });
  }
});

router.post('/room-types', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, [
  body('listingId').isUUID(),
  body('name').trim().isLength({ min: 2, max: 100 }),
  body('nightlyPriceTzs').isInt({ min: 0 }),
  body('capacity').isInt({ min: 1, max: 20 }),
  body('totalRooms').isInt({ min: 1 }),
  body('imageUrls').optional().isArray({ max: 12 }),
  body('imageUrls.*').optional().isURL({ protocols: ['https'], require_protocol: true }),
  body('primaryImageUrl').optional({ nullable: true }).isURL({ protocols: ['https'], require_protocol: true }),
  body('numberOfBeds').optional({ nullable: true }).isInt({ min: 1, max: 20 }),
  body('sizeSqm').optional({ nullable: true }).isFloat({ min: 0 }),
  body('amenityDetails').optional().isArray({ max: 100 }),
  body('amenityDetails.*.name').isString().trim().isLength({ min: 1, max: 100 }),
  body('amenityDetails.*.description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const property = await Property.findByPk(req.body.listingId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to add room types to this property' });
    }

    const fields = [
      'listingId', 'name', 'description', 'nightlyPriceTzs', 'currency',
      'capacity', 'totalRooms', 'amenities', 'imageUrls', 'primaryImageUrl',
      'bedType', 'numberOfBeds', 'bathroomType', 'sizeSqm', 'amenityDetails'
    ];
    const roomType = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await recheckInventoryProperty(property, req.user, transaction);
      return RoomType.create(Object.fromEntries(
        fields.filter((field) => Object.hasOwn(req.body, field))
          .map((field) => [field, req.body[field]])
      ), { transaction });
    });

    res.status(201).json({ message: 'Room type created successfully', roomType });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Create room type error:', error);
    res.status(500).json({ error: 'Failed to create room type' });
  }
});

router.put('/room-types/:id', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, [
  body('name').optional().isString().trim().isLength({ min: 2, max: 100 }),
  body('nightlyPriceTzs').optional().isInt({ min: 0 }).toInt(),
  body('capacity').optional().isInt({ min: 1, max: 20 }).toInt(),
  body('totalRooms').optional().isInt({ min: 1 }).toInt(),
  body('amenities').optional().isArray({ max: 100 }),
  body('amenities.*').optional().isString().trim().isLength({ min: 1, max: 500 }),
  body('imageUrls').optional().isArray({ max: 12 }),
  body('imageUrls.*').optional().isURL({ protocols: ['https'], require_protocol: true }),
  body('primaryImageUrl').optional({ nullable: true }).isURL({ protocols: ['https'], require_protocol: true }),
  body('numberOfBeds').optional({ nullable: true }).isInt({ min: 1, max: 20 }),
  body('sizeSqm').optional({ nullable: true }).isFloat({ min: 0 }),
  body('amenityDetails').optional().isArray({ max: 100 }),
  body('amenityDetails.*.name').optional().isString().trim().isLength({ min: 1, max: 100 }),
  body('amenityDetails.*.description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    const roomType = await RoomType.findByPk(req.params.id);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to update this room type' });
    }

    const fields = [
      'name', 'description', 'nightlyPriceTzs', 'currency', 'capacity',
      'totalRooms', 'amenities', 'imageUrls', 'primaryImageUrl', 'bedType',
      'numberOfBeds', 'bathroomType', 'sizeSqm', 'amenityDetails'
    ];
    const updates = Object.fromEntries(
      fields.filter((field) => Object.hasOwn(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await roomType.reload({ transaction });
      if (updates.totalRooms !== undefined) {
        const assigned = await Room.count({ where: { roomTypeId: roomType.id }, transaction });
        if (updates.totalRooms < assigned) {
          const error = new Error('Planned room count cannot be less than the number of assigned rooms');
          error.status = 409;
          throw error;
        }
      }
      if (updates.capacity !== undefined && updates.capacity < roomType.capacity) {
        const affected = await Booking.count({
          where: {
            roomTypeId: roomType.id, guestCount: { [Op.gt]: updates.capacity },
            checkOut: { [Op.gt]: new Date() },
            [Op.or]: [
              { status: 'confirmed' },
              { status: 'pending', holdExpiresAt: { [Op.gt]: new Date() } }
            ]
          }, transaction
        });
        if (affected) {
          const error = new Error('Capacity cannot be reduced below an active reservation guest count');
          error.status = 409;
          throw error;
        }
      }
      await roomType.update(updates, { transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'ROOM_CATEGORY_UPDATED', entityType: 'RoomType',
        entityId: roomType.id, metadata: { propertyId: property.id, fields: Object.keys(updates) },
        ipAddress: req.ip
      }, { transaction });
    });

    res.json({ message: 'Room type updated successfully', roomType });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Update room type error:', error);
    res.status(500).json({ error: 'Failed to update room type' });
  }
});

router.delete('/room-types/:id', authenticateToken, requireCapability('accommodationBooking'), requireVerifiedPhone, async (req, res) => {
  try {
    const roomType = await RoomType.findByPk(req.params.id);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to delete this room type' });
    }

    await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      const [rooms, bookings, walkIns] = await Promise.all([
        Room.count({ where: { roomTypeId: roomType.id }, transaction }),
        Booking.count({ where: { roomTypeId: roomType.id }, transaction }),
        WalkInReservation.count({ where: { roomTypeId: roomType.id }, transaction })
      ]);
      if (rooms || bookings || walkIns) {
        const error = new Error('Room categories with assigned rooms or reservation history cannot be deleted');
        error.status = 409;
        throw error;
      }
      await roomType.destroy({ transaction });
      await AdminAuditEvent.create({
        actorId: req.user.id, action: 'ROOM_CATEGORY_DELETED', entityType: 'RoomType',
        entityId: roomType.id, metadata: { propertyId: property.id }, ipAddress: req.ip
      }, { transaction });
    });

    res.json({ message: 'Room type deleted successfully' });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Delete room type error:', error);
    res.status(500).json({ error: 'Failed to delete room type' });
  }
});

// Room Inventory Management
router.get('/inventory/:roomTypeId', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const roomType = await RoomType.findByPk(req.params.roomTypeId);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this inventory' });
    }

    const inventory = await RoomInventory.findAll({
      where: { roomTypeId: req.params.roomTypeId },
      order: [['date', 'ASC']]
    });

    res.json({ inventory });
  } catch (error) {
    console.error('Get inventory error:', error);
    res.status(500).json({ error: 'Failed to fetch inventory' });
  }
});

router.post('/inventory', authenticateToken, requireCapability('accommodationBooking'), [
  body('roomTypeId').isUUID(),
  body('date').isISO8601(),
  body('booked').isInt({ min: 0 }),
  body('totalOverride').optional().isInt({ min: 0 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const roomType = await RoomType.findByPk(req.body.roomTypeId);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to manage this inventory' });
    }

    const inventory = await RoomInventory.findOne({
      where: {
        roomTypeId: req.body.roomTypeId,
        date: req.body.date
      }
    });

    if (inventory) {
      await inventory.update(req.body);
    } else {
      await RoomInventory.create(req.body);
    }

    res.json({ message: 'Inventory updated successfully' });
  } catch (error) {
    console.error('Update inventory error:', error);
    res.status(500).json({ error: 'Failed to update inventory' });
  }
});

// Check-in Policy Management
router.get('/checkin-policy/:listingId', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.listingId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to view this policy' });
    }

    const policy = await CheckInPolicy.findOne({
      where: { listingId: req.params.listingId }
    });

    res.json({ policy: policy || {} });
  } catch (error) {
    console.error('Get check-in policy error:', error);
    res.status(500).json({ error: 'Failed to fetch check-in policy' });
  }
});

router.put('/checkin-policy/:listingId', authenticateToken, requireCapability('accommodationBooking'), [
  body('checkInFrom').optional().matches(/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/),
  body('checkOutBy').optional().matches(/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/),
  body('cancellationHours').optional().isInt({ min: 0, max: 168 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const property = await Property.findByPk(req.params.listingId);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to update this policy' });
    }

    const policy = await CheckInPolicy.findOne({
      where: { listingId: req.params.listingId }
    });

    if (policy) {
      await policy.update(req.body);
    } else {
      await CheckInPolicy.create({
        ...req.body,
        listingId: req.params.listingId
      });
    }

    res.json({ message: 'Check-in policy updated successfully' });
  } catch (error) {
    console.error('Update check-in policy error:', error);
    res.status(500).json({ error: 'Failed to update check-in policy' });
  }
});

// Guest Messaging
router.get('/rental-conversations', authenticateToken, async (req, res) => {
  try {
    let unlockWhere;
    if (req.user.role === 'CUSTOMER') {
      unlockWhere = { customerId: req.user.id, status: 'active' };
    } else if (req.user.hasCapability('rentalProperty')) {
      const listings = await Property.findAll({
        where: { agentId: req.user.id, businessModel: 'contactUnlock' },
        attributes: ['id']
      });
      unlockWhere = {
        listingId: listings.map((listing) => listing.id),
        status: 'active'
      };
    } else {
      return res.status(403).json({ error: 'You do not have permission to view rental conversations' });
    }

    const unlocks = await UnlockRecord.findAll({
      where: unlockWhere,
      include: [
        { model: Property, as: 'property', attributes: ['id', 'name', 'city', 'neighborhood', 'imageUrl', 'agentId'] },
        { model: User, as: 'customer', attributes: ['id', 'fullName'] },
        { model: PaymentTransaction, as: 'transaction' }
      ],
      order: [['updatedAt', 'DESC']]
    });
    const conversations = [];
    for (const unlock of unlocks) {
      const customerId = unlock.customerId;
      if (!validRentalUnlock(unlock, customerId, unlock.listingId)) continue;
      const access = await rentalMessageAccess(unlock.listingId, customerId, req.user);
      if (!access) continue;
      const lastMessage = await RentalMessage.findOne({
        where: { listingId: unlock.listingId, customerId },
        order: [['createdAt', 'DESC']],
        include: [{ model: User, as: 'sender', attributes: ['id', 'fullName'] }]
      });
      const unreadCount = await RentalMessage.count({
        where: {
          listingId: unlock.listingId,
          customerId,
          senderId: { [Op.ne]: req.user.id },
          readAt: null
        }
      });
      conversations.push({
        listingId: unlock.listingId,
        customerId,
        property: rentalPropertySummary(access.property),
        customer: req.user.role === 'CUSTOMER' ? undefined : unlock.customer,
        lastMessage,
        unreadCount
      });
    }
    res.json({ conversations });
  } catch (error) {
    console.error('List rental conversations error:', error);
    res.status(500).json({ error: 'Failed to fetch rental conversations' });
  }
});

router.get('/rental-messages/:listingId/:customerId', authenticateToken, async (req, res) => {
  try {
    const access = await rentalMessageAccess(
      req.params.listingId,
      req.params.customerId,
      req.user
    );
    if (!access) {
      return res.status(403).json({ error: 'A verified contact unlock is required for this conversation' });
    }
    await RentalMessage.update(
      { readAt: new Date() },
      {
        where: {
          listingId: req.params.listingId,
          customerId: req.params.customerId,
          senderId: { [Op.ne]: req.user.id },
          readAt: null
        }
      }
    );
    const messages = await RentalMessage.findAll({
      where: { listingId: req.params.listingId, customerId: req.params.customerId },
      include: [{ model: User, as: 'sender', attributes: ['id', 'fullName'] }],
      order: [['createdAt', 'ASC']]
    });
    res.json({ property: rentalPropertySummary(access.property), messages });
  } catch (error) {
    console.error('Get rental messages error:', error);
    res.status(500).json({ error: 'Failed to fetch rental messages' });
  }
});

router.post('/rental-messages', authenticateToken, messageLimiter, [
  body('listingId').isUUID(),
  body('customerId').isUUID(),
  body('body').trim().isLength({ min: 1, max: 2000 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }
    const { listingId, customerId, body: messageBody } = req.body;
    const access = await rentalMessageAccess(listingId, customerId, req.user);
    if (!access) {
      return res.status(403).json({ error: 'A verified contact unlock is required for this conversation' });
    }
    const message = await RentalMessage.create({
      listingId,
      customerId,
      senderId: req.user.id,
      body: messageBody
    });
    const recipientId = access.isAgent ? customerId : access.property.agentId;
    await notify(
      recipientId,
      access.isAgent ? 'CUSTOMER' : 'RENTAL_AGENT',
      'New rental message',
      `You have a new message about ${access.property.name}.`,
      '/account/messages',
      'Open message'
    );
    res.status(201).json({ message: 'Message sent successfully', data: message });
  } catch (error) {
    console.error('Send rental message error:', error);
    res.status(500).json({ error: 'Failed to send rental message' });
  }
});

router.get('/messages/:bookingId', authenticateToken, async (req, res) => {
  try {
    const booking = await Booking.findByPk(req.params.bookingId);
    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    if (!await messageAccess(booking, req.user, false)) {
      return res.status(403).json({ error: 'You do not have permission to view these messages' });
    }

    const messages = await GuestMessage.findAll({
      where: { bookingId: req.params.bookingId },
      include: [
        {
          model: User,
          as: 'sender',
          attributes: ['id', 'fullName']
        }
      ],
      order: [['createdAt', 'ASC']]
    });

    res.json({ messages });
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

router.post('/messages', authenticateToken, messageLimiter, [
  body('bookingId').isUUID(),
  body('body').trim().isLength({ min: 1, max: 2000 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const booking = await Booking.findByPk(req.body.bookingId);
    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    const access = await messageAccess(booking, req.user, true);
    if (!access) {
      return res.status(403).json({ error: 'You do not have permission to send messages to this booking' });
    }

    const senderType = access.isAgent ? 'agent' : 'guest';

    const message = await GuestMessage.create({
      bookingId: req.body.bookingId,
      senderId: req.user.id,
      senderType,
      body: req.body.body
    });

    const recipient = access.isAgent ? booking.customerId : access.property.agentId;
    await notify(recipient, access.isAgent ? 'CUSTOMER' : 'STAY_AGENT',
      'New booking message', 'You have a new message about your stay.');

    res.status(201).json({ message: 'Message sent successfully', data: message });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// Agent Profile Management
router.get('/profile', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT'), async (req, res) => {
  try {
    const [agentProfile] = await AgentProfile.findOrCreate({
      where: { userId: req.user.id }
    });
    const profile = {
      userId: req.user.id,
      displayName: req.user.fullName,
      agencyName: agentProfile.agencyName,
      bio: agentProfile.bio,
      photoUrl: agentProfile.photoUrl,
      videoUrl: agentProfile.videoUrl,
      serviceAreas: agentProfile.serviceAreas,
      role: req.user.role,
      capabilities: req.user.capabilities,
      phone: req.user.phone,
      email: req.user.email,
      verification: req.user.verification
    };

    res.json({ profile });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

router.put('/profile', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT'), [
  body('displayName').optional().trim().isLength({ min: 2, max: 100 }),
  body('agencyName').optional({ checkFalsy: true }).trim().isLength({ max: 100 }),
  body('bio').optional({ checkFalsy: true }).trim().isLength({ max: 500 }),
  body('photoUrl').optional({ checkFalsy: true }).isURL({ require_protocol: true }).isLength({ max: 1000 }),
  body('videoUrl').optional({ checkFalsy: true }).isURL({ require_protocol: true }).isLength({ max: 1000 }),
  body('serviceAreas').optional().isArray({ max: 50 }),
  body('serviceAreas.*').optional().isString().trim().isLength({ min: 1, max: 100 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { displayName, ...profileUpdates } = req.body;
    if (displayName) await req.user.update({ fullName: displayName });
    const [profile] = await AgentProfile.findOrCreate({
      where: { userId: req.user.id },
      defaults: profileUpdates
    });
    if (Object.keys(profileUpdates).length > 0) {
      await profile.update(profileUpdates);
    }

    res.json({
      message: 'Profile updated successfully',
      profile: {
        userId: req.user.id,
        displayName: req.user.fullName,
        agencyName: profile.agencyName,
        bio: profile.bio,
        photoUrl: profile.photoUrl,
        videoUrl: profile.videoUrl,
        serviceAreas: profile.serviceAreas,
        role: req.user.role,
        capabilities: req.user.capabilities,
        phone: req.user.phone,
        email: req.user.email,
        verification: req.user.verification
      }
    });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
