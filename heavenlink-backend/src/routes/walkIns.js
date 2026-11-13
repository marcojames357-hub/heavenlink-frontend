const express = require('express');
const { createHash } = require('crypto');
const { body, validationResult } = require('express-validator');
const { Op, Transaction } = require('sequelize');
const {
  sequelize, Property, Room, WalkInReservation, WalkInRoomSegment, AdminAuditEvent
} = require('../models');
const { authenticateToken, requireCapability, requireVerifiedPhone } = require('../middleware/auth');
const { unavailableRoomIds } = require('../services/roomAvailability');
const { hasWorkspace } = require('../services/workspaces');

const router = express.Router();
router.use(authenticateToken, requireCapability('accommodationBooking'));
router.use(async (req, res, next) => {
  try {
    if (await hasWorkspace(req.user, 'HOTEL')) return next();
    res.status(403).json({ error: 'The Hotel, Lodge & Motel workspace is not enabled for this account' });
  } catch (error) { next(error); }
});

const propertyForRequest = async (req, res) => {
  const property = await Property.findByPk(req.params.listingId);
  if (!property || property.businessModel !== 'bookable' ||
      !['hotel', 'motel', 'lodge'].includes(property.accommodationType || property.category)) {
    res.status(404).json({ error: 'Multi-room accommodation not found' });
    return null;
  }
  if (property.agentId !== req.user.id && req.user.role !== 'ADMIN') {
    res.status(403).json({ error: 'You do not have permission to manage this property' });
    return null;
  }
  return property;
};

const fail = (status, message) => {
  const error = new Error(message);
  error.status = status;
  throw error;
};

const audit = (req, reservation, action, transaction, metadata = {}) =>
  AdminAuditEvent.create({
    actorId: req.user.id, action, entityType: 'WalkInReservation',
    entityId: reservation.id, metadata: { propertyId: reservation.propertyId, ...metadata },
    ipAddress: req.ip
  }, { transaction });

const handleError = (res, error) => {
  if (error.status) return res.status(error.status).json({ error: error.message });
  console.error('Walk-in reservation error:', error);
  return res.status(500).json({ error: 'Failed to manage walk-in reservation' });
};

const validation = (req, res) => {
  const errors = validationResult(req);
  if (errors.isEmpty()) return true;
  res.status(400).json({ error: 'Validation failed', details: errors.array() });
  return false;
};

router.get('/:listingId', async (req, res) => {
  try {
    const property = await propertyForRequest(req, res);
    if (!property) return;
    const reservations = await WalkInReservation.findAll({
      where: { propertyId: property.id },
      include: [
        { model: Room, as: 'room', attributes: ['id', 'roomNumber'] },
        {
          model: WalkInRoomSegment, as: 'roomSegments',
          attributes: ['id', 'roomId', 'startAt', 'endAt'],
          include: [{ model: Room, as: 'room', attributes: ['roomNumber'] }]
        }
      ],
      order: [['checkIn', 'DESC']],
      limit: 500
    });
    res.json({ reservations });
  } catch (error) {
    handleError(res, error);
  }
});

router.post('/:listingId', requireVerifiedPhone, [
  body('requestKey').isString().trim().isLength({ min: 1, max: 200 }),
  body('roomId').isUUID(),
  body('guestName').isString().trim().isLength({ min: 2, max: 100 }),
  body('guestPhone').optional({ nullable: true }).isString().trim().isLength({ max: 40 }),
  body('checkIn').isISO8601(),
  body('checkOut').isISO8601(),
  body('priceTzs').isInt({ min: 0, max: 2000000000 }).toInt(),
  body('paymentStatus').isIn(['unpaid', 'partiallyPaid', 'paid']),
  body('notes').optional({ nullable: true }).isString().trim().isLength({ max: 1000 }),
  body('checkInNow').optional().isBoolean({ strict: true })
], async (req, res) => {
  if (!validation(req, res)) return;
  try {
    const property = await propertyForRequest(req, res);
    if (!property) return;
    const data = req.body;
    const start = new Date(data.checkIn);
    const end = new Date(data.checkOut);
    const now = new Date();
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) ||
        end <= start) {
      return res.status(400).json({ error: 'Provide a valid stay period' });
    }
    const fingerprint = createHash('sha256').update(JSON.stringify([
      property.id, req.user.id, data.roomId, data.guestName, data.guestPhone || null,
      start.toISOString(), end.toISOString(), data.priceTzs, data.paymentStatus,
      data.notes || null, Boolean(data.checkInNow)
    ])).digest('hex');
    let replayed = false;
    const reservation = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      const currentProperty = await Property.findByPk(property.id, { transaction });
      if (!currentProperty || currentProperty.businessModel !== 'bookable' ||
          !['hotel', 'motel', 'lodge'].includes(currentProperty.accommodationType || currentProperty.category) ||
          (currentProperty.agentId !== req.user.id && req.user.role !== 'ADMIN')) {
        fail(409, 'Property inventory or permissions changed. Refresh and try again.');
      }
      const previous = await WalkInReservation.findOne({ where: { requestKey: data.requestKey }, transaction });
      if (previous) {
        if (previous.requestFingerprint !== fingerprint) {
          fail(409, 'Request key is already used for a different walk-in');
        }
        replayed = true;
        return previous;
      }
      if (end <= now || (data.checkInNow && start > now)) {
        fail(400, 'Immediate check-in cannot be in the future and checkout must be in the future');
      }
      const room = await Room.findOne({
        where: { id: data.roomId, propertyId: property.id, status: 'active' }, transaction
      });
      if (!room || !room.roomTypeId) fail(400, 'Choose an active room with an assigned category');
      if ((await unavailableRoomIds([room.id], start, end, { transaction })).has(room.id)) {
        const alternatives = await Room.findAll({
          where: { propertyId: property.id, roomTypeId: room.roomTypeId, status: 'active' },
          attributes: ['id', 'roomNumber'], order: [['roomNumber', 'ASC']], transaction
        });
        const unavailable = await unavailableRoomIds(alternatives.map((candidate) => candidate.id), start, end, { transaction });
        const available = alternatives.filter((candidate) => !unavailable.has(candidate.id)).slice(0, 5);
        fail(409, available.length
          ? `Room is unavailable for the selected dates. Available alternatives: ${available.map((candidate) => candidate.roomNumber).join(', ')}.`
          : 'Room is unavailable for the selected dates. No other rooms in this category are available.');
      }
      const created = await WalkInReservation.create({
        propertyId: property.id, roomId: room.id, roomTypeId: room.roomTypeId,
        createdById: req.user.id, requestKey: data.requestKey, requestFingerprint: fingerprint, guestName: data.guestName,
        guestPhone: data.guestPhone || null, checkIn: start, checkOut: end,
        checkedInAt: data.checkInNow ? now : null,
        priceTzs: data.priceTzs, paymentStatus: data.paymentStatus, notes: data.notes || null,
        status: data.checkInNow ? 'checkedIn' : 'reserved'
      }, { transaction });
      await WalkInRoomSegment.create({
        walkInReservationId: created.id, roomId: room.id, startAt: start, endAt: end
      }, { transaction });
      await audit(req, created, 'WALK_IN_CREATED', transaction, { roomId: room.id });
      return created;
    });
    res.status(replayed ? 200 : 201).json({ reservation });
  } catch (error) {
    handleError(res, error);
  }
});

router.post('/:listingId/:id/:action', requireVerifiedPhone, [
  body('checkOut').optional().isISO8601(),
  body('roomId').optional().isUUID(),
  body('paymentStatus').optional().isIn(['unpaid', 'partiallyPaid', 'paid']),
  body('reason').optional().isString().trim().isLength({ min: 3, max: 500 })
], async (req, res) => {
  if (!validation(req, res)) return;
  try {
    const property = await propertyForRequest(req, res);
    if (!property) return;
    const action = req.params.action;
    if (!['check-in', 'extend', 'change-room', 'payment', 'checkout', 'cancel'].includes(action)) {
      return res.status(404).json({ error: 'Unknown walk-in action' });
    }
    const reservation = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      const stay = await WalkInReservation.findOne({ where: { id: req.params.id, propertyId: property.id }, transaction });
      if (!stay) fail(404, 'Walk-in reservation not found');
      if (!['reserved', 'checkedIn'].includes(stay.status)) fail(409, 'This reservation is already closed');
      const now = new Date();
      const metadata = { roomId: stay.roomId };
      if (action === 'check-in') {
        if (stay.status !== 'reserved' || stay.checkIn > now || stay.checkOut <= now) {
          fail(409, 'Check-in is only available during the reserved stay');
        }
        const activeRoom = await Room.findOne({
          where: { id: stay.roomId, propertyId: property.id, roomTypeId: stay.roomTypeId, status: 'active' },
          transaction
        });
        if (!activeRoom) fail(409, 'Room is no longer active in this category');
        if ((await unavailableRoomIds([stay.roomId], now, stay.checkOut, {
          transaction, excludeWalkInId: stay.id
        })).has(stay.roomId)) fail(409, 'Room is no longer available for this stay');
        await stay.update({ status: 'checkedIn', checkedInAt: now }, { transaction });
      } else if (action === 'checkout') {
        if (stay.status !== 'checkedIn') fail(409, 'The guest has not checked in');
        await stay.update({ status: 'completed', checkedOutAt: now }, { transaction });
        const segment = await WalkInRoomSegment.findOne({
          where: { walkInReservationId: stay.id, endAt: { [Op.gt]: now } },
          order: [['startAt', 'DESC']], transaction
        });
        if (segment) await segment.update({ endAt: now }, { transaction });
      } else if (action === 'cancel') {
        if (!req.body.reason) fail(400, 'A cancellation reason is required');
        if (stay.status === 'checkedIn') fail(409, 'Check out an occupied room instead of cancelling');
        await stay.update({ status: 'cancelled' }, { transaction });
        await WalkInRoomSegment.update(
          { endAt: stay.checkIn < now ? now : stay.checkIn },
          { where: { walkInReservationId: stay.id, endAt: { [Op.gt]: stay.checkIn } }, transaction }
        );
        metadata.reason = req.body.reason;
      } else if (action === 'payment') {
        if (!req.body.paymentStatus) fail(400, 'Payment status is required');
        metadata.previousStatus = stay.paymentStatus;
        await stay.update({ paymentStatus: req.body.paymentStatus }, { transaction });
      } else {
        if (action === 'extend') {
          if (!req.body.checkOut) fail(400, 'New checkout is required');
          const end = new Date(req.body.checkOut);
          if (Number.isNaN(end.getTime()) || end <= stay.checkOut || end <= now) fail(400, 'New checkout must extend the stay');
          const segment = await WalkInRoomSegment.findOne({
            where: { walkInReservationId: stay.id, endAt: stay.checkOut },
            order: [['startAt', 'DESC']], transaction
          });
          if (!segment) fail(409, 'Room stay history is unavailable; refresh and try again');
          if ((await unavailableRoomIds([segment.roomId], stay.checkOut, end, {
            transaction, excludeWalkInId: stay.id
          })).has(segment.roomId)) fail(409, 'Room is unavailable for the extension');
          await segment.update({ endAt: end }, { transaction });
          await stay.update({ checkOut: end }, { transaction });
          metadata.roomId = segment.roomId;
          metadata.previousCheckOut = stay.checkOut;
        } else {
          if (!req.body.roomId) fail(400, 'A replacement room is required');
          if (!req.body.reason) fail(400, 'A room-change reason is required');
          if (stay.checkOut <= now) fail(409, 'An overdue stay must be checked out before changing rooms');
          const room = await Room.findOne({
            where: { id: req.body.roomId, propertyId: property.id, roomTypeId: stay.roomTypeId, status: 'active' },
            transaction
          });
          if (!room || room.id === stay.roomId) fail(400, 'Choose another active room in the same category');
          const effectiveStart = stay.status === 'checkedIn'
            ? new Date(Math.max(now.getTime(), stay.checkIn.getTime()))
            : stay.checkIn;
          if ((await unavailableRoomIds([room.id], effectiveStart, stay.checkOut, {
            transaction, excludeWalkInId: stay.id
          })).has(room.id)) fail(409, 'Room is unavailable for the remaining stay');
          const currentSegment = await WalkInRoomSegment.findOne({
            where: { walkInReservationId: stay.id, endAt: stay.checkOut },
            order: [['startAt', 'DESC']], transaction
          });
          if (!currentSegment) fail(409, 'Room stay history is unavailable; refresh and try again');
          metadata.previousRoomId = currentSegment.roomId;
          metadata.newRoomId = room.id;
          metadata.effectiveAt = effectiveStart;
          metadata.reason = req.body.reason;
          if (stay.status === 'checkedIn') {
            if (effectiveStart <= currentSegment.startAt) {
              await currentSegment.update({ roomId: room.id }, { transaction });
            } else {
              await currentSegment.update({ endAt: effectiveStart }, { transaction });
              await WalkInRoomSegment.create({
                walkInReservationId: stay.id,
                roomId: room.id,
                startAt: effectiveStart,
                endAt: stay.checkOut
              }, { transaction });
            }
          } else {
            await currentSegment.update({ roomId: room.id }, { transaction });
          }
          await stay.update({ roomId: room.id }, { transaction });
        }
      }
      await audit(req, stay, `WALK_IN_${action.replace('-', '_').toUpperCase()}`, transaction, metadata);
      return stay;
    });
    res.json({ reservation });
  } catch (error) {
    handleError(res, error);
  }
});

module.exports = router;
