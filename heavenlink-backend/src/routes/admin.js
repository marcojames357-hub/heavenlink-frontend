const express = require('express');
const { body, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const { User, Property, Booking, PaymentTransaction, UnlockRecord, Notification, BusinessConfiguration, AdminAuditEvent, Review, ReviewReport, Room, RoomType, Floor, WalkInReservation, sequelize } = require('../models');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// Admin configuration
const DEFAULT_UNLOCK_FEE = parseInt(process.env.DEFAULT_UNLOCK_FEE_TZS) || 5000;
const BOOKING_FEE_RATE = parseFloat(process.env.BOOKING_FEE_RATE) || 0.02;
const MAX_BOOKING_FEE_RATE = parseFloat(process.env.MAX_BOOKING_FEE_RATE) || 0.25;

const getBusinessConfiguration = async () => {
  const [config] = await BusinessConfiguration.findOrCreate({
    where: { id: 1 },
    defaults: {
      unlockFeeTzs: DEFAULT_UNLOCK_FEE,
      bookingFeeRate: BOOKING_FEE_RATE
    }
  });
  return config;
};

const logAdminEvent = (req, action, entityType, entityId, metadata = {}) =>
  AdminAuditEvent.create({
    actorId: req.user.id,
    action,
    entityType,
    entityId: String(entityId),
    metadata,
    ipAddress: req.ip
  });

router.get('/room-inventory', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const properties = await Property.findAll({
      where: {
        businessModel: 'bookable',
        [Op.or]: [
          { accommodationType: { [Op.in]: ['hotel', 'motel', 'lodge'] } },
          { category: { [Op.in]: ['hotel', 'lodge'] } }
        ]
      },
      attributes: ['id', 'name', 'category', 'accommodationType', 'listingStatus'],
      order: [['name', 'ASC']]
    });
    const inventory = await Promise.all(properties.map(async (property) => {
      const [rooms, bookings, walkIns] = await Promise.all([
        Room.findAll({
          where: { propertyId: property.id },
          include: [
            { model: RoomType, as: 'roomType', attributes: ['name'] },
            { model: Floor, as: 'floor', attributes: ['label'] }
          ],
          order: [['roomNumber', 'ASC']]
        }),
        Booking.findAll({
          where: {
            propertyId: property.id,
            status: { [Op.in]: ['pending', 'confirmed'] }
          },
          attributes: ['id', 'roomTypeId', 'assignedRoomId', 'checkIn', 'checkOut', 'status'],
          include: [
            { model: Room, as: 'assignedRoom', attributes: ['roomNumber'] }
          ],
          order: [['checkIn', 'ASC']]
        }),
        WalkInReservation.findAll({
          where: { propertyId: property.id, status: { [Op.in]: ['reserved', 'checkedIn'] } },
          attributes: ['id', 'guestName', 'checkIn', 'checkOut', 'status', 'paymentStatus', 'priceTzs'],
          include: [
            { model: RoomType, as: 'roomType', attributes: ['name'] },
            { model: Room, as: 'room', attributes: ['roomNumber'] }
          ],
          order: [['checkIn', 'ASC']]
        })
      ]);
      const typeNames = new Map((await RoomType.findAll({
        where: { listingId: property.id }, attributes: ['id', 'name']
      })).map((type) => [type.id, type.name]));
      return {
        property: {
          id: property.id,
          name: property.name,
          category: property.accommodationType || property.category,
          listingStatus: property.listingStatus
        },
        totalRooms: rooms.length,
        walkIns: walkIns.map((stay) => ({
          id: stay.id,
          guestName: stay.guestName,
          checkIn: stay.checkIn,
          checkOut: stay.checkOut,
          status: stay.status,
          paymentStatus: stay.paymentStatus,
          priceTzs: stay.priceTzs,
          category: stay.roomType?.name ?? null,
          room: stay.room?.roomNumber ?? null
        })),
        assignedRooms: rooms.filter((room) => room.roomTypeId != null).length,
        outOfServiceRooms: rooms.filter((room) => room.status === 'outOfService').length,
        rooms: rooms.map((room) => ({
          id: room.id,
          roomNumber: room.roomNumber,
          floor: room.floor?.label ?? null,
          category: room.roomType?.name ?? null,
          status: room.status
        })),
        bookings: bookings.map((booking) => ({
          id: booking.id,
          checkIn: booking.checkIn,
          checkOut: booking.checkOut,
          status: booking.status,
          category: typeNames.get(booking.roomTypeId) ?? null,
          assignedRoom: booking.assignedRoom?.roomNumber ?? null
        }))
      };
    }));
    res.json({ inventory });
  } catch (error) {
    console.error('Get admin room inventory error:', error);
    res.status(500).json({ error: 'Failed to fetch room inventory' });
  }
});

router.get('/audit-events', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 200);
    const events = await AdminAuditEvent.findAll({
      limit,
      include: [{ model: User, as: 'actor', attributes: ['id', 'fullName', 'email'] }],
      order: [['createdAt', 'DESC']]
    });
    res.json({ events });
  } catch (error) {
    console.error('Get audit events error:', error.message);
    res.status(500).json({ error: 'Failed to fetch audit events' });
  }
});

router.get('/reviews', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const page = Math.max(Number.parseInt(req.query.page, 10) || 1, 1);
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 25, 1), 100);
    const where = {};
    if (['published', 'hidden', 'rejected'].includes(req.query.status)) {
      where.status = req.query.status;
    }
    const reportWhere = req.query.reportedOnly === 'true' ? { status: 'pending' } : undefined;
    if (req.query.propertyId) where.propertyId = String(req.query.propertyId);
    const createdRange = {};
    const from = new Date(req.query.from);
    const to = new Date(req.query.to);
    if (!Number.isNaN(from.getTime())) createdRange[Op.gte] = from;
    if (!Number.isNaN(to.getTime())) createdRange[Op.lte] = new Date(to.getTime() + 86400000 - 1);
    if (Reflect.ownKeys(createdRange).length) where.createdAt = createdRange;
    const propertyWhere = req.query.agentId ? { agentId: String(req.query.agentId) } : undefined;
    const { count, rows } = await Review.findAndCountAll({
      where,
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood', 'agentId'],
          where: propertyWhere,
          required: Boolean(propertyWhere)
        },
        { model: User, as: 'reviewer', attributes: ['id', 'fullName', 'email'] },
        {
          model: ReviewReport,
          as: 'reportRecords',
          where: reportWhere,
          required: Boolean(reportWhere),
          include: [{ model: User, as: 'reporter', attributes: ['id', 'fullName', 'email'] }]
        }
      ],
      distinct: true,
      order: [['createdAt', 'DESC']],
      limit,
      offset: (page - 1) * limit
    });
    const [published, pendingReports, total, hidden, rejected] = await Promise.all([
      Review.findAll({ where: { status: 'published' }, attributes: ['overallRating'] }),
      ReviewReport.count({ where: { status: 'pending' } }),
      Review.count(),
      Review.count({ where: { status: 'hidden' } }),
      Review.count({ where: { status: 'rejected' } })
    ]);
    const averageRating = published.length
      ? Number((published.reduce((sum, review) => sum + review.overallRating, 0) / published.length).toFixed(2))
      : 0;

    res.json({
      reviews: rows,
      pagination: { page, limit, total: count, pages: Math.ceil(count / limit) },
      stats: {
        published: published.length,
        hidden,
        rejected,
        pendingReports,
        averageRating,
        total
      }
    });
  } catch (error) {
    console.error('Get review moderation queue error:', error.message);
    res.status(500).json({ error: 'Failed to fetch review moderation queue' });
  }
});

router.patch('/reviews/:id/moderation', authenticateToken, requireRole('ADMIN'), [
  body('status').isIn(['published', 'hidden', 'rejected']),
  body('reason').trim().isLength({ min: 5, max: 1000 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'A valid status and moderation reason are required' });
  }
  const transaction = await sequelize.transaction();
  try {
    const review = await Review.findByPk(req.params.id, { transaction });
    if (!review) {
      await transaction.rollback();
      return res.status(404).json({ error: 'Review not found' });
    }
    const previousStatus = review.status;
    await review.update({
      status: req.body.status,
      moderationReason: req.body.reason.trim()
    }, { transaction });
    await ReviewReport.update(
      { status: 'resolved' },
      { where: { reviewId: review.id, status: 'pending' }, transaction }
    );
    await AdminAuditEvent.create({
      actorId: req.user.id,
      action: 'REVIEW_MODERATED',
      entityType: 'Review',
      entityId: review.id,
      metadata: {
        previousStatus,
        status: review.status,
        reason: req.body.reason.trim()
      },
      ipAddress: req.ip
    }, { transaction });
    await transaction.commit();
    res.json({ message: 'Review moderation saved', review });
  } catch (error) {
    await transaction.rollback();
    console.error('Moderate review error:', error.message);
    res.status(500).json({ error: 'Failed to moderate review' });
  }
});

// Get all users
router.get('/users', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { role, verification, search } = req.query;
    
    const where = {};
    if (role) where.role = role;
    if (verification) where.verification = verification;
    if (search) {
      where[Op.or] = [
        { fullName: { [Op.like]: `%${search}%` } },
        { email: { [Op.like]: `%${search}%` } },
        { phone: { [Op.like]: `%${search}%` } }
      ];
    }

    const users = await User.findAll({
      where,
      attributes: { exclude: ['password'] },
      order: [['createdAt', 'DESC']]
    });

    res.json({ users });
  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Get single user
router.get('/users/:id', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const user = await User.findByPk(req.params.id, {
      attributes: { exclude: ['password'] }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Update user
router.put('/users/:id', authenticateToken, requireRole('ADMIN'), [
  body('role').optional().isIn(['CUSTOMER', 'RENTAL_AGENT', 'STAY_AGENT', 'ADMIN']),
  body('verification').optional().isIn(['unverified', 'pending', 'verified']),
  body('accountEnabled').optional().isBoolean(),
  body('capabilities').optional().isArray(),
  body('capabilities.*').optional().isIn(['rentalProperty', 'accommodationBooking'])
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const user = await User.findByPk(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const editableFields = ['role', 'verification', 'accountEnabled', 'capabilities'];
    const updates = Object.fromEntries(
      editableFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    await user.update(updates);
    await logAdminEvent(req, 'USER_UPDATED', 'User', user.id, {
      changedFields: Object.keys(updates)
    });

    res.json({
      message: 'User updated successfully',
      user: await User.findByPk(user.id, { attributes: { exclude: ['password'] } })
    });
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ error: 'Failed to update user' });
  }
});

// Enable/disable user account
router.patch('/users/:id/status', authenticateToken, requireRole('ADMIN'), [
  body('accountEnabled').isBoolean()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const user = await User.findByPk(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    await user.update({ accountEnabled: req.body.accountEnabled });
    await logAdminEvent(req, 'USER_STATUS_CHANGED', 'User', user.id, {
      accountEnabled: req.body.accountEnabled
    });

    res.json({ message: `User account ${req.body.accountEnabled ? 'enabled' : 'disabled'}` });
  } catch (error) {
    console.error('Update user status error:', error);
    res.status(500).json({ error: 'Failed to update user status' });
  }
});

// Get all properties (including non-public)
router.get('/properties', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { businessModel, status, city, agentId } = req.query;
    
    const where = {};
    if (businessModel) where.businessModel = businessModel;
    if (status) where.listingStatus = status;
    if (city) where.city = city;
    if (agentId) where.agentId = agentId;

    const properties = await Property.findAll({
      where,
      include: [
        {
          model: User,
          as: 'agent',
          attributes: ['id', 'fullName', 'email', 'phone']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ properties });
  } catch (error) {
    console.error('Get properties error:', error);
    res.status(500).json({ error: 'Failed to fetch properties' });
  }
});

// Approve/reject property
router.patch('/properties/:id/status', authenticateToken, requireRole('ADMIN'), [
  body('status').isIn(['draft', 'pendingReview', 'published', 'paused', 'rejected'])
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const property = await Property.findByPk(req.params.id);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    await property.update({ listingStatus: req.body.status });
    await logAdminEvent(req, 'LISTING_STATUS_CHANGED', 'Property', property.id, {
      status: req.body.status
    });

    // Send notification to agent
    await Notification.create({
      userId: property.agentId,
      title: `Property ${req.body.status}`,
      message: `Your property "${property.name}" has been ${req.body.status}.`,
      audience: property.agentId === req.user.id ? null : req.user.role
    });

    res.json({ message: 'Property status updated successfully', property });
  } catch (error) {
    console.error('Update property status error:', error);
    res.status(500).json({ error: 'Failed to update property status' });
  }
});

// Get all bookings
router.get('/bookings', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { status, propertyId, customerId } = req.query;
    
    const where = {};
    if (status) where.status = status;
    if (propertyId) where.propertyId = propertyId;
    if (customerId) where.customerId = customerId;

    const bookings = await Booking.findAll({
      where,
      include: [
        {
          model: Property,
          as: 'property',
          attributes: ['id', 'name', 'city', 'neighborhood']
        },
        {
          model: User,
          as: 'customer',
          attributes: ['id', 'fullName', 'email', 'phone']
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

// Get all payment transactions
router.get('/transactions', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { status, purpose, methodId } = req.query;
    
    const where = {};
    if (status) where.status = status;
    if (purpose) where.purpose = purpose;
    if (methodId) where.methodId = methodId;

    const transactions = await PaymentTransaction.findAll({
      where,
      include: [
        {
          model: User,
          as: 'customer',
          attributes: ['id', 'fullName', 'email']
        },
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
    console.error('Get transactions error:', error);
    res.status(500).json({ error: 'Failed to fetch transactions' });
  }
});

// Get all unlock records
router.get('/unlocks', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { status, listingId, customerId } = req.query;
    
    const where = {};
    if (status) where.status = status;
    if (listingId) where.listingId = listingId;
    if (customerId) where.customerId = customerId;

    const unlocks = await UnlockRecord.findAll({
      where,
      include: [
        {
          model: User,
          as: 'customer',
          attributes: ['id', 'fullName', 'email']
        },
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
    console.error('Get unlocks error:', error);
    res.status(500).json({ error: 'Failed to fetch unlock records' });
  }
});

// Business configuration management
router.get('/config', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const stored = await getBusinessConfiguration();
    const config = {
      unlockFeeTzs: stored.unlockFeeTzs,
      bookingFeeRate: stored.bookingFeeRate,
      maxBookingFeeRate: MAX_BOOKING_FEE_RATE,
      currency: 'TZS'
    };

    res.json({ config });
  } catch (error) {
    console.error('Get config error:', error);
    res.status(500).json({ error: 'Failed to fetch configuration' });
  }
});

router.put('/config', authenticateToken, requireRole('ADMIN'), [
  body('unlockFeeTzs').optional().isInt({ min: 500, max: 50000 }),
  body('bookingFeeRate').optional().isFloat({ min: 0, max: MAX_BOOKING_FEE_RATE })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const stored = await getBusinessConfiguration();
    await stored.update({
      unlockFeeTzs: req.body.unlockFeeTzs ?? stored.unlockFeeTzs,
      bookingFeeRate: req.body.bookingFeeRate ?? stored.bookingFeeRate
    });
    await logAdminEvent(req, 'BUSINESS_FEES_UPDATED', 'BusinessConfiguration', 1, {
      unlockFeeTzs: stored.unlockFeeTzs,
      bookingFeeRate: stored.bookingFeeRate
    });
    const config = {
      unlockFeeTzs: stored.unlockFeeTzs,
      bookingFeeRate: stored.bookingFeeRate,
      maxBookingFeeRate: MAX_BOOKING_FEE_RATE,
      currency: 'TZS'
    };

    res.json({ message: 'Configuration updated successfully', config });
  } catch (error) {
    console.error('Update config error:', error);
    res.status(500).json({ error: 'Failed to update configuration' });
  }
});

// Get all notifications
router.get('/notifications', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const { audience, isRead } = req.query;
    
    const where = {};
    if (audience) where.audience = audience;
    if (isRead !== undefined) where.isRead = isRead;

    const notifications = await Notification.findAll({
      where,
      include: [
        {
          model: User,
          as: 'user',
          attributes: ['id', 'fullName', 'email']
        }
      ],
      order: [['createdAt', 'DESC']]
    });

    res.json({ notifications });
  } catch (error) {
    console.error('Get notifications error:', error);
    res.status(500).json({ error: 'Failed to fetch notifications' });
  }
});

// Create system notification
router.post('/notifications', authenticateToken, requireRole('ADMIN'), [
  body('title').trim().isLength({ min: 2, max: 200 }),
  body('message').trim().isLength({ min: 5, max: 1000 }),
  body('audience').optional().isIn(['CUSTOMER', 'RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'])
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { title, message, audience, actionUrl, actionLabel } = req.body;

    // Send to all users of the specified audience
    const where = audience ? { role: audience } : {};
    const users = await User.findAll({ where });

    const notifications = await Promise.all(
      users.map(user =>
        Notification.create({
          userId: user.id,
          title,
          message,
          audience,
          actionUrl,
          actionLabel
        })
      )
    );

    res.status(201).json({ 
      message: `Notification sent to ${notifications.length} users`,
      count: notifications.length
    });
  } catch (error) {
    console.error('Create notification error:', error);
    res.status(500).json({ error: 'Failed to create notification' });
  }
});

// Get dashboard statistics
router.get('/dashboard', authenticateToken, requireRole('ADMIN'), async (req, res) => {
  try {
    const totalUsers = await User.count();
    const totalProperties = await Property.count();
    const publishedProperties = await Property.count({ where: { listingStatus: 'published' } });
    const pendingProperties = await Property.count({ where: { listingStatus: 'pendingReview' } });
    const totalBookings = await Booking.count();
    const activeBookings = await Booking.count({ where: { status: 'confirmed' } });
    const totalTransactions = await PaymentTransaction.count();
    const totalRevenue = await PaymentTransaction.sum('amountTzs', {
      where: { status: 'succeeded' }
    });
    const totalUnlocks = await UnlockRecord.count({ where: { status: 'active' } });

    const stats = {
      users: {
        total: totalUsers,
        customers: await User.count({ where: { role: 'CUSTOMER' } }),
        rentalAgents: await User.count({ where: { role: 'RENTAL_AGENT' } }),
        stayAgents: await User.count({ where: { role: 'STAY_AGENT' } })
      },
      properties: {
        total: totalProperties,
        published: publishedProperties,
        pending: pendingProperties,
        rentals: await Property.count({ where: { businessModel: 'contactUnlock' } }),
        accommodations: await Property.count({ where: { businessModel: 'bookable' } })
      },
      bookings: {
        total: totalBookings,
        active: activeBookings,
        pending: await Booking.count({ where: { status: 'pending' } }),
        completed: await Booking.count({ where: { status: 'completed' } })
      },
      transactions: {
        total: totalTransactions,
        succeeded: await PaymentTransaction.count({ where: { status: 'succeeded' } }),
        failed: await PaymentTransaction.count({ where: { status: 'failed' } }),
        totalRevenue: totalRevenue || 0
      },
      unlocks: {
        total: totalUnlocks,
        pending: await UnlockRecord.count({ where: { status: 'awaitingPayment' } }),
        failed: await UnlockRecord.count({ where: { status: 'failed' } })
      }
    };

    res.json({ stats });
  } catch (error) {
    console.error('Get dashboard stats error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard statistics' });
  }
});

module.exports = router;
