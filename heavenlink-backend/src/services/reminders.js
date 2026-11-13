const { Op } = require('sequelize');
const {
  Booking, Property, Room, CheckInPolicy, RentObligation, RentReceipt
} = require('../models');
const { notify, retrySmsDeliveries } = require('./notify');
const { bookingReference } = require('./bookingConfirmation');

// Properties are in Tanzania (UTC+3, no DST).
const UTC_OFFSET_HOURS = 3;
const HOUR = 3600000;
const CHECKIN_LEAD_HOURS = Number(process.env.CHECKIN_REMINDER_HOURS) || 24;
const CHECKOUT_LEAD_HOURS = Number(process.env.CHECKOUT_REMINDER_HOURS) || 24;
const CHECKOUT_DAY_HOUR = Number(process.env.CHECKOUT_DAY_REMINDER_HOUR) || 7;
const DEFAULT_RENT_OFFSETS = [7, 3, 0, -3]; // days until due; negative = days overdue
const MAX_RENT_OFFSETS = 6;
const MAX_OFFSET_DAYS = 30;

const localParts = (instant) => {
  const shifted = new Date(instant.getTime() + UTC_OFFSET_HOURS * HOUR);
  return { date: shifted.toISOString().slice(0, 10), hour: shifted.getUTCHours() };
};
const atLocalTime = (instant, hhmm) => {
  const [hour, minute] = hhmm.split(':').map(Number);
  const { date } = localParts(instant);
  return new Date(Date.parse(`${date}T00:00:00Z`) + (hour - UTC_OFFSET_HOURS) * HOUR + minute * 60000);
};
const dayNumber = (dateString) => Math.floor(Date.parse(`${dateString}T00:00:00Z`) / 86400000);
const formatTime = (hhmm) => {
  const [hour, minute] = hhmm.split(':').map(Number);
  return `${hour % 12 || 12}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`;
};

const sanitizeOffsets = (offsets) => {
  if (!Array.isArray(offsets) || offsets.length === 0 || offsets.length > MAX_RENT_OFFSETS) return null;
  const clean = [...new Set(offsets)];
  return clean.every((value) => Number.isInteger(value) && Math.abs(value) <= MAX_OFFSET_DAYS) ? clean : null;
};

async function runBookingReminders(now = new Date()) {
  const bookings = await Booking.findAll({
    where: { status: 'confirmed', checkedOutAt: null, checkOut: { [Op.gt]: now } },
    include: [{ model: Property, as: 'property', attributes: ['id', 'name', 'agentId'] }]
  });
  let created = 0;
  for (const booking of bookings) {
    const policy = await CheckInPolicy.findOne({ where: { listingId: booking.propertyId } });
    const checkInAt = atLocalTime(new Date(booking.checkIn), policy?.checkInFrom || '14:00');
    const checkOutTime = policy?.checkOutBy || '11:00';
    const checkOutAt = atLocalTime(new Date(booking.checkOut), checkOutTime);
    const reference = bookingReference(booking);
    const name = booking.property.name;
    const base = { propertyId: booking.propertyId, bookingId: booking.id };
    const track = (result) => { if (result) created += 1; };

    const untilCheckIn = checkInAt - now;
    if (untilCheckIn > 0 && untilCheckIn <= CHECKIN_LEAD_HOURS * HOUR) {
      track(await notify(booking.customerId, 'CUSTOMER', 'Upcoming check-in',
        `Haven Link Reminder: your stay at ${name} starts soon. Check-in is from ${formatTime(policy?.checkInFrom || '14:00')} on ${localParts(checkInAt).date}. Booking ${reference}. Open My Bookings for details.`,
        `/bookings/${booking.id}`, 'View booking', {
          ...base, type: 'CHECKIN_REMINDER', category: 'checkin',
          dedupeKey: `checkin:${booking.id}:${checkInAt.toISOString()}`
        }));
    }

    const untilCheckOut = checkOutAt - now;
    if (now >= checkInAt && untilCheckOut > 0) {
      const today = localParts(now);
      const dueDay = localParts(checkOutAt).date;
      const when = dayNumber(dueDay) === dayNumber(today.date) ? 'today' : 'tomorrow';
      const stamp = checkOutAt.toISOString();
      if (untilCheckOut <= CHECKOUT_LEAD_HOURS * HOUR) {
        track(await notify(booking.customerId, 'CUSTOMER', 'Checkout reminder',
          `Haven Link Reminder: your stay at ${name} ends ${when}. Checkout is at ${formatTime(checkOutTime)}. Open My Bookings for details.`,
          `/bookings/${booking.id}`, 'View booking', {
            ...base, type: 'CHECKOUT_REMINDER', category: 'checkout', dedupeKey: `checkout-lead:${booking.id}:${stamp}`
          }));
        const room = booking.assignedRoomId ? await Room.findByPk(booking.assignedRoomId, { attributes: ['roomNumber'] }) : null;
        track(await notify(booking.property.agentId, 'STAY_AGENT', 'Upcoming guest departure',
          `${room ? `Room ${room.roomNumber}` : name} — guest checkout scheduled ${when} at ${formatTime(checkOutTime)}. Booking ${reference}.`,
          `/agent/reservations/${booking.id}`, 'Open reservation', {
            ...base, type: 'CHECKOUT_ALERT_AGENT', category: 'checkout', sms: false,
            dedupeKey: `checkout-agent:${booking.id}:${stamp}`
          }));
      }
      if (today.date === dueDay && today.hour >= CHECKOUT_DAY_HOUR) {
        track(await notify(booking.customerId, 'CUSTOMER', 'Checkout today',
          `Haven Link Reminder: checkout at ${name} is today at ${formatTime(checkOutTime)}. Booking ${reference}.`,
          `/bookings/${booking.id}`, 'View booking', {
            ...base, type: 'CHECKOUT_DAY_REMINDER', category: 'checkout', dedupeKey: `checkout-day:${booking.id}:${stamp}`
          }));
      }
    }
  }
  return created;
}

async function outstandingFor(obligation) {
  const receipts = await RentReceipt.findAll({ where: { obligationId: obligation.id, reversedAt: null } });
  const paid = receipts.reduce((sum, receipt) => sum + receipt.amountTzs, 0);
  return { paid, outstanding: Math.max(0, obligation.expectedTzs - paid) };
}

// Only obligations explicitly linked to a verified tenant account produce reminders.
async function runRentReminders(now = new Date()) {
  const obligations = await RentObligation.findAll({
    where: { tenantUserId: { [Op.ne]: null }, tenancyEndedAt: null },
    include: [{ model: Property, as: 'property', attributes: ['id', 'name', 'agentId'] }]
  });
  const today = dayNumber(localParts(now).date);
  let created = 0;
  for (const obligation of obligations) {
    if (obligation.leaseEndDate && !obligation.tenancyEndedAt) {
      const daysToEnd = dayNumber(obligation.leaseEndDate) - today;
      if ([30, 7].includes(daysToEnd)) {
        const result = await notify(obligation.property.agentId, 'RENTAL_AGENT', 'Lease ending soon',
          `${obligation.property.name} (${obligation.unitReference}): lease ends in ${daysToEnd} days.`,
          `/agent/rent/${obligation.id}`, 'Open tenancy', {
            type: 'LEASE_EXPIRY', category: 'rent', sms: false, propertyId: obligation.propertyId,
            dedupeKey: `lease-end:${obligation.id}:${obligation.leaseEndDate}:${daysToEnd}`
          });
        if (result) created += 1;
      }
    }
    const { outstanding, paid } = await outstandingFor(obligation);
    if (outstanding <= 0) continue;
    const offsets = sanitizeOffsets(obligation.reminderOffsets) || DEFAULT_RENT_OFFSETS;
    const daysUntilDue = dayNumber(obligation.dueDate) - today;
    if (!offsets.includes(daysUntilDue)) continue;
    const label = obligation.unitReference;
    const partial = paid > 0 ? ` An outstanding balance remains on your statement.` : '';
    const text = daysUntilDue > 0
      ? `Your rent for ${obligation.property.name} (${label}), period ${obligation.billingMonth}, is due in ${daysUntilDue} day${daysUntilDue === 1 ? '' : 's'}.${partial}`
      : daysUntilDue === 0
        ? `Your rent for ${obligation.property.name} (${label}), period ${obligation.billingMonth}, is due today.${partial}`
        : `Your rent for ${obligation.property.name} (${label}), period ${obligation.billingMonth}, is overdue. Please review your rental statement.${partial}`;
    const key = `rent:${obligation.id}:${obligation.dueDate}:${daysUntilDue}`;
    const meta = { propertyId: obligation.propertyId, category: 'rent' };
    if (await notify(obligation.tenantUserId, 'CUSTOMER', daysUntilDue < 0 ? 'Rent overdue' : 'Rent reminder', text,
      `/rental-statements/${obligation.id}`, 'View statement', {
        ...meta, type: daysUntilDue < 0 ? 'RENT_OVERDUE' : 'RENT_DUE',
        priority: daysUntilDue < 0 ? 'high' : 'normal', dedupeKey: key
      })) created += 1;
    if (daysUntilDue <= 3) {
      if (await notify(obligation.property.agentId, 'RENTAL_AGENT',
        daysUntilDue < 0 ? 'Rent overdue' : 'Rent due soon',
        `${obligation.property.name} (${label}), ${obligation.billingMonth}: TZS ${outstanding} outstanding, due ${obligation.dueDate}.`,
        `/agent/rent/${obligation.id}`, 'Open rent record', {
          ...meta, type: daysUntilDue < 0 ? 'RENT_OVERDUE_AGENT' : 'RENT_DUE_AGENT', sms: false,
          priority: daysUntilDue < 0 ? 'high' : 'normal', dedupeKey: `${key}:agent`
        })) created += 1;
    }
  }
  return created;
}

async function runReminders(now = new Date()) {
  const bookings = await runBookingReminders(now);
  const rent = await runRentReminders(now);
  await retrySmsDeliveries();
  return { bookings, rent };
}

let timer = null;
function startReminderScheduler() {
  if (timer) return timer;
  const run = () => runReminders().catch((error) => console.error('Reminder run failed:', error));
  timer = setInterval(run, 15 * 60 * 1000);
  timer.unref();
  run();
  return timer;
}

module.exports = {
  runReminders, runBookingReminders, runRentReminders, startReminderScheduler,
  sanitizeOffsets, localParts, atLocalTime
};
