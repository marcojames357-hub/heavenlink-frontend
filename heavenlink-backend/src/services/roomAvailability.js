const { Op } = require('sequelize');
const {
  Booking, WalkInReservation, WalkInRoomSegment, RoomAvailabilityBlock
} = require('../models');

const unavailableRoomIds = async (roomIds, checkIn, checkOut, options = {}) => {
  if (!roomIds.length) return new Set();
  const { transaction, excludeBookingId, excludeWalkInId } = options;
  const bookingWhere = {
    assignedRoomId: { [Op.in]: roomIds },
    checkIn: { [Op.lt]: checkOut },
    checkOut: { [Op.gt]: checkIn },
    [Op.or]: [
      { status: 'confirmed' },
      { status: 'pending', holdExpiresAt: { [Op.gt]: new Date() } }
    ]
  };
  if (excludeBookingId) bookingWhere.id = { [Op.ne]: excludeBookingId };
  const segmentWhere = {
    roomId: { [Op.in]: roomIds },
    startAt: { [Op.lt]: checkOut },
    endAt: { [Op.gt]: checkIn }
  };
  const reservationWhere = { status: { [Op.in]: ['reserved', 'checkedIn'] } };
  if (excludeWalkInId) reservationWhere.id = { [Op.ne]: excludeWalkInId };
  const end = new Date(checkOut);
  const endDay = end.toISOString().slice(0, 10);
  const blockEnd = end.getTime() === Date.parse(`${endDay}T00:00:00.000Z`)
    ? endDay
    : new Date(Date.parse(`${endDay}T00:00:00.000Z`) + 86400000).toISOString().slice(0, 10);
  const [bookings, walkIns, blocks] = await Promise.all([
    Booking.findAll({ where: bookingWhere, attributes: ['assignedRoomId'], transaction }),
    WalkInRoomSegment.findAll({
      where: segmentWhere,
      attributes: ['roomId'],
      include: [{
        model: WalkInReservation, as: 'reservation', where: reservationWhere,
        attributes: [], required: true
      }],
      transaction
    }),
    RoomAvailabilityBlock.findAll({
      where: {
        roomId: { [Op.in]: roomIds },
        startDate: { [Op.lt]: blockEnd },
        endDate: { [Op.gt]: new Date(checkIn).toISOString().slice(0, 10) }
      },
      attributes: ['roomId'],
      transaction
    })
  ]);
  return new Set([
    ...bookings.map((item) => item.assignedRoomId),
    ...walkIns.map((item) => item.roomId),
    ...blocks.map((item) => item.roomId)
  ]);
};

module.exports = { unavailableRoomIds };
