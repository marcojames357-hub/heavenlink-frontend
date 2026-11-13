const { Op } = require('sequelize');
const { Notification, NotificationPreference } = require('../models');

const MAX_SMS_ATTEMPTS = 3;
// Only transactional categories may be sent over SMS.
const SMS_CATEGORIES = new Set(['booking', 'checkin', 'checkout', 'rent', 'payment']);
const GROUPS = {
  bookings: ['booking', 'checkin', 'checkout'],
  payments: ['payment', 'finance'],
  messages: ['message'],
  reviews: ['review', 'report'],
  rent: ['rent'],
  admin: ['admin']
};

// Legacy callers pass no category, so derive it from their destination or title.
const inferCategory = (title = '', actionUrl = '') => {
  if (/report/i.test(actionUrl) || /report|concern/i.test(title)) return 'report';
  if (/review/i.test(actionUrl) || /review/i.test(title)) return 'review';
  if (/message/i.test(title)) return 'message';
  return 'general';
};

const smsService = () => require('./smsService');

// Provider acceptance is recorded as "sent"; only a provider callback could mean "delivered".
async function attemptSms(notification, phone) {
  const channels = { ...(notification.channels || {}) };
  const attempts = (channels.sms?.attempts || 0) + 1;
  try {
    const result = await smsService().sendMessage(phone, `${notification.title}: ${notification.message}`);
    channels.sms = { status: 'sent', attempts, provider: result.provider, providerMessageId: result.messageId };
  } catch (error) {
    channels.sms = {
      status: attempts >= MAX_SMS_ATTEMPTS ? 'failed' : 'retry',
      attempts,
      lastError: String(error.message || error).slice(0, 200)
    };
  }
  await notification.update({ channels });
}

// Notification text must never carry confidential report or payment details.
// options: { type, category, priority, propertyId, bookingId, dedupeKey, sms }
const notify = async (userId, audience, title, message, actionUrl, actionLabel, options = {}) => {
  if (!userId) return null;
  try {
    const category = options.category || inferCategory(title, actionUrl);
    if (options.dedupeKey) {
      const existing = await Notification.findOne({ where: { userId, dedupeKey: options.dedupeKey } });
      if (existing) return null;
    }
    const preference = await NotificationPreference.findOne({ where: { userId } });
    if (preference && (preference.mutedCategories || []).includes(category) && options.priority !== 'critical') {
      return null;
    }
    const wantsSms = options.sms !== false && SMS_CATEGORIES.has(category) && (!preference || preference.sms);
    const channels = {
      inApp: { status: 'delivered' },
      sms: { status: wantsSms ? 'queued' : 'skipped', attempts: 0 },
      email: { status: 'not_configured' }
    };
    const notification = await Notification.create({
      userId, audience, title, message, actionUrl, actionLabel,
      type: options.type || null, category,
      priority: options.priority || 'normal',
      propertyId: options.propertyId || null, bookingId: options.bookingId || null,
      dedupeKey: options.dedupeKey || null, channels
    });
    if (wantsSms) {
      const { User } = require('../models');
      const user = await User.findByPk(userId, { attributes: ['phone'] });
      if (user?.phone && smsService().isConfigured()) {
        await attemptSms(notification, user.phone);
      } else {
        await notification.update({ channels: { ...channels, sms: { status: 'not_configured', attempts: 0 } } });
      }
    }
    return notification;
  } catch (error) {
    if (error.name === 'SequelizeUniqueConstraintError') return null;
    console.error('Create notification error:', error.message);
    return null;
  }
};

async function retrySmsDeliveries(limit = 50) {
  const { User } = require('../models');
  const recent = await Notification.findAll({
    where: { createdAt: { [Op.gt]: new Date(Date.now() - 86400000) } }, limit: 500
  });
  let retried = 0;
  for (const notification of recent) {
    if (retried >= limit) break;
    if (notification.channels?.sms?.status !== 'retry') continue;
    const user = await User.findByPk(notification.userId, { attributes: ['phone'] });
    if (user?.phone && smsService().isConfigured()) {
      await attemptSms(notification, user.phone);
      retried += 1;
    }
  }
  return retried;
}

const notifyAdmins = async (title, message, actionUrl, options = {}) => {
  const { User } = require('../models');
  const admins = await User.findAll({ where: { role: 'ADMIN' }, attributes: ['id'] });
  await Promise.all(admins.map((admin) => notify(
    admin.id, 'ADMIN', title, message, actionUrl, 'Open', { category: 'admin', ...options }
  )));
};

module.exports = { notify, notifyAdmins, retrySmsDeliveries, GROUPS };
