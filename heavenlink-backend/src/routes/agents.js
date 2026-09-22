const express = require('express');
const { body, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const { Property, Booking, RoomType, RoomInventory, CheckInPolicy, GuestMessage, Notification, UnlockRecord, User } = require('../models');
const { authenticateToken, requireRole, requireCapability, requireVerifiedPhone } = require('../middleware/auth');

const router = express.Router();

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
          attributes: ['id', 'name', 'city', 'neighborhood']
        }
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
  body('totalRooms').isInt({ min: 1 })
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

    const roomType = await RoomType.create(req.body);

    res.status(201).json({ message: 'Room type created successfully', roomType });
  } catch (error) {
    console.error('Create room type error:', error);
    res.status(500).json({ error: 'Failed to create room type' });
  }
});

router.put('/room-types/:id', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const roomType = await RoomType.findByPk(req.params.id);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to update this room type' });
    }

    await roomType.update(req.body);

    res.json({ message: 'Room type updated successfully', roomType });
  } catch (error) {
    console.error('Update room type error:', error);
    res.status(500).json({ error: 'Failed to update room type' });
  }
});

router.delete('/room-types/:id', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const roomType = await RoomType.findByPk(req.params.id);
    if (!roomType) {
      return res.status(404).json({ error: 'Room type not found' });
    }

    const property = await Property.findByPk(roomType.listingId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to delete this room type' });
    }

    await roomType.destroy();

    res.json({ message: 'Room type deleted successfully' });
  } catch (error) {
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
router.get('/messages/:bookingId', authenticateToken, requireCapability('accommodationBooking'), async (req, res) => {
  try {
    const booking = await Booking.findByPk(req.params.bookingId);
    if (!booking) {
      return res.status(404).json({ error: 'Booking not found' });
    }

    const property = await Property.findByPk(booking.propertyId);
    if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
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

router.post('/messages', authenticateToken, requireRole('STAY_AGENT', 'ADMIN', 'CUSTOMER'), [
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

    // Check permissions
    const property = await Property.findByPk(booking.propertyId);
    const isAgent = property.agentId === req.user.id;
    const isCustomer = booking.customerId === req.user.id;

    if (!isAgent && !isCustomer && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'You do not have permission to send messages to this booking' });
    }

    const senderType = isAgent ? 'agent' : 'guest';

    const message = await GuestMessage.create({
      bookingId: req.body.bookingId,
      senderId: req.user.id,
      senderType,
      body: req.body.body
    });

    res.status(201).json({ message: 'Message sent successfully', data: message });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// Agent Profile Management
router.get('/profile', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT'), async (req, res) => {
  try {
    const profile = {
      userId: req.user.id,
      displayName: req.user.fullName,
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
  body('agencyName').optional().trim().isLength({ min: 2, max: 100 }),
  body('bio').optional().trim().isLength({ min: 10, max: 500 }),
  body('serviceAreas').optional().isArray()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    // Update user profile (in a real app, this would be in a separate AgentProfile table)
    const updates = {};
    if (req.body.displayName) updates.fullName = req.body.displayName;

    await req.user.update(updates);

    res.json({ message: 'Profile updated successfully' });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
