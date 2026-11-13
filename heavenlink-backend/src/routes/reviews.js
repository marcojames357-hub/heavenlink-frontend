const express = require('express');
const fs = require('fs');
const rateLimit = require('express-rate-limit');
const { body, validationResult } = require('express-validator');
const { Op, Transaction } = require('sequelize');
const {
  sequelize, Booking, Property, Review, ReviewReport, User, ProblemReport
} = require('../models');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { acceptFiles, storeFiles, removeFiles, filePath } = require('../services/uploads');
const { notify } = require('../services/notify');
const { getBookingPayment, matchesBookingPayment, isVerifiedBookingPayment } = require('../services/bookingPayment');

const router = express.Router();
const ratingFields = Review.ratingFields;
const REVIEW_WINDOW_DAYS = 14;
const mentionTopics = [
  { label: 'Hospitality', pattern: /\b(host|hospitality|staff|welcome|welcoming|friendly|service)\b/i },
  { label: 'View', pattern: /\b(view|scenery|ocean|sea|mountain|lake|sunset)\b/i },
  { label: 'Decor', pattern: /\b(decor|decoration|interior|design|stylish|furniture)\b/i },
  { label: 'Accuracy', pattern: /\b(accurate|accuracy|description|as described|photos|advertised)\b/i }
];

const cleanedText = (value, maxLength) => {
  if (typeof value !== 'string') return null;
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/<[^>]*>/g, '')
    .trim()
    .slice(0, maxLength) || null;
};

const submissionLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 30,
  keyGenerator: (req) => req.user?.id || req.ip,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many submissions. Please try again later.' }
});

const average = (values) => values.length
  ? Number((values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(2))
  : 0;

// Overall comes from the independent Overall Experience ratings, never from category averages.
const buildSummary = (reviews) => {
  const distribution = { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 };
  const mentions = new Map();
  for (const review of reviews) {
    distribution[Math.max(1, Math.min(5, Math.round(review.overallRating)))] += 1;
    const text = `${review.title || ''} ${review.comment || ''}`;
    for (const topic of mentionTopics) {
      if (topic.pattern.test(text)) mentions.set(topic.label, (mentions.get(topic.label) || 0) + 1);
    }
  }
  return {
    count: reviews.length,
    overall: average(reviews.map((review) => Number(review.overallRating))),
    criteria: Object.fromEntries(ratingFields.map((field) => [
      field,
      average(reviews.map((review) => review[field]).filter((value) => value != null).map(Number))
    ])),
    distribution,
    mentions: [...mentions.entries()].map(([label, count]) => ({ label, count }))
      .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
  };
};

const displayName = (fullName) => {
  const parts = String(fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'Haven Link guest';
  return parts.length === 1 ? parts[0] : `${parts[0]} ${parts[parts.length - 1][0]}.`;
};

const photoUrls = (review) => (review.images || [])
  .map((name) => `/api/v1/reviews/photos/${name}`);

const publicReview = (review) => {
  const row = review.toJSON();
  const stayDate = row.booking?.checkOut || null;
  delete row.bookingId;
  delete row.booking;
  delete row.reviewerId;
  delete row.moderationReason;
  delete row.agentResponderId;
  row.images = photoUrls(review);
  row.stayDate = stayDate;
  if (row.reviewer) row.reviewer = { displayName: displayName(row.reviewer.fullName) };
  return row;
};

const ownReview = (review) => {
  const row = review.toJSON();
  delete row.moderationReason;
  delete row.agentResponderId;
  row.images = photoUrls(review);
  return row;
};

// Server-side eligibility; never derived from the client-side booking status or dates.
const reviewEligibility = async (booking, existingReview, payment = undefined, transaction = undefined) => {
  if (booking.property?.businessModel !== 'bookable') {
    return { eligible: false, reason: 'Only Stays can be reviewed' };
  }
  if (existingReview) return { eligible: false, reason: 'This stay already has a review' };
  if (booking.status !== 'completed' || !booking.checkedOutAt ||
      new Date(booking.checkedOutAt).getTime() > Date.now()) {
    return { eligible: false, reason: 'The stay has not been completed and checked out yet' };
  }
  const deadline = new Date(new Date(booking.checkedOutAt).getTime() + REVIEW_WINDOW_DAYS * 86400000);
  if (Date.now() > deadline.getTime()) {
    return { eligible: false, reason: `The ${REVIEW_WINDOW_DAYS}-day review window has closed`, deadline };
  }
  if (payment === undefined) payment = await getBookingPayment(booking, transaction);
  if (!isVerifiedBookingPayment(booking, payment)) {
    return { eligible: false, reason: 'Payment verification for this booking is incomplete', deadline };
  }
  return { eligible: true, deadline };
};

const tripPhase = (booking) => {
  const now = Date.now();
  if (booking.status === 'cancelled') return 'cancelled';
  if (booking.status === 'completed') return 'completed';
  if (new Date(booking.checkIn).getTime() > now) return 'upcoming';
  return booking.status === 'confirmed' ? 'ongoing' : 'upcoming';
};

const tripSerializer = async (booking, review, reportCount) => {
  const payment = await getBookingPayment(booking);
  const eligibility = await reviewEligibility(booking, review, payment);
  const paymentStatus = !booking.paymentTransactionId ? 'not_recorded'
    : isVerifiedBookingPayment(booking, payment) ? 'verified'
    : matchesBookingPayment(booking, payment) && payment.status !== 'succeeded'
      ? payment.status : 'unverified';
  const nights = Math.max(1, Math.round(
    (new Date(booking.checkOut) - new Date(booking.checkIn)) / 86400000
  ));
  return {
    id: booking.id,
    reference: booking.requestKey || booking.id,
    property: booking.property,
    checkIn: booking.checkIn,
    checkOut: booking.checkOut,
    nights,
    status: booking.status,
    phase: tripPhase(booking),
    paymentStatus,
    totalTzs: booking.totalTzs,
    checkedOutAt: booking.checkedOutAt,
    canReview: eligibility.eligible,
    reviewBlockedReason: eligibility.eligible ? null : eligibility.reason,
    reviewDeadline: eligibility.deadline || null,
    reportCount,
    review: review ? ownReview(review) : null
  };
};

const loadTrips = async (customerId, statuses) => {
  const bookings = await Booking.findAll({
    where: { customerId, status: { [Op.in]: statuses } },
    include: [{
      model: Property,
      as: 'property',
      where: { businessModel: 'bookable' },
      attributes: ['id', 'name', 'city', 'neighborhood', 'imageUrl', 'businessModel']
    }],
    order: [['checkIn', 'DESC']]
  });
  const ids = bookings.map((booking) => booking.id);
  const reviews = ids.length ? await Review.findAll({ where: { bookingId: { [Op.in]: ids } } }) : [];
  const reports = ids.length
    ? await ProblemReport.findAll({ where: { bookingId: { [Op.in]: ids } }, attributes: ['bookingId'] })
    : [];
  const reportCounts = new Map();
  for (const report of reports) {
    reportCounts.set(report.bookingId, (reportCounts.get(report.bookingId) || 0) + 1);
  }
  const reviewByBooking = new Map(reviews.map((review) => [review.bookingId, review]));
  return Promise.all(bookings.map((booking) => tripSerializer(
    booking, reviewByBooking.get(booking.id), reportCounts.get(booking.id) || 0
  )));
};

// Completed stays with their review state (kept for existing clients).
router.get('/mine', authenticateToken, requireRole('CUSTOMER'), async (req, res) => {
  try {
    res.json({ bookings: await loadTrips(req.user.id, ['completed']) });
  } catch (error) {
    console.error('Get eligible reviews error:', error.message);
    res.status(500).json({ error: 'Failed to fetch review eligibility' });
  }
});

// All of the customer's Stays bookings for the Upcoming / Ongoing / Completed tabs.
router.get('/trips', authenticateToken, requireRole('CUSTOMER'), async (req, res) => {
  try {
    res.json({ trips: await loadTrips(req.user.id, ['pending', 'confirmed', 'completed']) });
  } catch (error) {
    console.error('Get trips error:', error.message);
    res.status(500).json({ error: 'Failed to fetch trips' });
  }
});

router.get('/eligibility/:bookingId', authenticateToken, requireRole('CUSTOMER'), async (req, res) => {
  try {
    const booking = await Booking.findOne({
      where: { id: req.params.bookingId, customerId: req.user.id },
      include: [{ model: Property, as: 'property' }]
    });
    if (!booking) return res.status(404).json({ error: 'Booking not found' });
    const review = await Review.findOne({ where: { bookingId: booking.id } });
    const result = await reviewEligibility(booking, review);
    res.json({ eligible: result.eligible, reason: result.reason || null, deadline: result.deadline || null });
  } catch (error) {
    console.error('Check eligibility error:', error.message);
    res.status(500).json({ error: 'Failed to check eligibility' });
  }
});

router.post('/', authenticateToken, requireRole('CUSTOMER'), submissionLimiter,
  acceptFiles('photos'), [
    body('bookingId').isUUID(),
    body('overallRating').isInt({ min: 1, max: 5 }),
    ...ratingFields.map((field) => body(field).isInt({ min: 1, max: 5 })),
    body('title').optional({ nullable: true }).isString().isLength({ max: 120 }),
    body('comment').optional({ nullable: true }).isString().isLength({ max: 3000 })
  ], async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }
    const comment = cleanedText(req.body.comment, 3000);
    if (typeof req.body.comment === 'string' && req.body.comment.trim() && (!comment || comment.length < 10)) {
      return res.status(400).json({ error: 'Your written review must be at least 10 characters' });
    }

    let stored = [];
    try {
      const booking = await Booking.findOne({
        where: { id: req.body.bookingId, customerId: req.user.id },
        include: [{ model: Property, as: 'property' }]
      });
      if (!booking) {
        return res.status(403).json({ error: 'Only the customer on a completed stay may review it' });
      }
      const eligibility = await reviewEligibility(booking, null);
      if (!eligibility.eligible) {
        return res.status(403).json({ error: eligibility.reason });
      }

      stored = await storeFiles(req.files, 'review-photos', { allowPdf: false });
      const ratings = Object.fromEntries(
        ratingFields.map((field) => [field, Number(req.body[field])])
      );
      const review = await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
        if (await Review.findOne({ where: { bookingId: booking.id }, transaction })) {
          const conflict = new Error('This stay already has a review');
          conflict.status = 409;
          throw conflict;
        }
        await booking.reload({ include: [{ model: Property, as: 'property' }], transaction });
        const currentEligibility = await reviewEligibility(booking, null, undefined, transaction);
        if (!currentEligibility.eligible) {
          const error = new Error(currentEligibility.reason);
          error.status = 403;
          throw error;
        }
        return Review.create({
          ...ratings,
          overallRating: Number(req.body.overallRating),
          bookingId: booking.id,
          propertyId: booking.propertyId,
          reviewerId: req.user.id,
          title: cleanedText(req.body.title, 120),
          comment,
          images: stored,
          status: 'published',
          publishedAt: new Date()
        }, { transaction });
      });

      await notify(req.user.id, 'CUSTOMER', 'Thank you for your review',
        'Thank you for sharing your experience.', '/account/reviews', 'View review');
      await notify(booking.property.agentId, 'STAY_AGENT', 'New guest review',
        'A guest has reviewed one of your properties.', '/agent/reviews', 'View reviews');
      res.status(201).json({ message: 'Review submitted', review: ownReview(review) });
    } catch (error) {
      await removeFiles('review-photos', stored);
      if (error.status === 409 || error.name === 'SequelizeUniqueConstraintError') {
        return res.status(409).json({ error: 'This stay already has a review' });
      }
      if (error.status === 403) return res.status(403).json({ error: error.message });
      if (error.status === 400) return res.status(400).json({ error: error.message });
      console.error('Submit review error:', error.message);
      res.status(500).json({ error: 'Failed to submit review' });
    }
  });

// Photos are only public while their review is published.
router.get('/photos/:name', async (req, res) => {
  try {
    const target = filePath('review-photos', req.params.name);
    if (!target) return res.status(404).json({ error: 'Photo not found' });
    const review = await Review.findOne({
      where: {
        status: 'published',
        [Op.and]: [sequelize.where(
          sequelize.cast(sequelize.col('images'), 'TEXT'),
          { [Op.like]: `%${req.params.name}%` }
        )]
      },
      attributes: ['id']
    });
    if (!review || !fs.existsSync(target)) return res.status(404).json({ error: 'Photo not found' });
    res.set('Cache-Control', 'public, max-age=3600');
    res.set('X-Content-Type-Options', 'nosniff');
    res.sendFile(target);
  } catch (error) {
    console.error('Serve review photo error:', error.message);
    res.status(500).json({ error: 'Failed to load photo' });
  }
});

router.get('/properties/:propertyId', async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.propertyId);
    if (!property || !property.isPublic() || property.businessModel !== 'bookable') {
      return res.status(404).json({ error: 'Public stay not found' });
    }
    const page = Math.max(Number.parseInt(req.query.page, 10) || 1, 1);
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 6, 1), 30);
    const sort = ['highest', 'lowest'].includes(req.query.sort) ? req.query.sort : 'newest';
    const order = sort === 'highest'
      ? [['overallRating', 'DESC'], ['createdAt', 'DESC']]
      : sort === 'lowest'
        ? [['overallRating', 'ASC'], ['createdAt', 'DESC']]
        : [['createdAt', 'DESC']];

    const where = { propertyId: property.id, status: 'published' };
    const ratingFilter = Number.parseInt(req.query.rating, 10);
    if (ratingFilter >= 1 && ratingFilter <= 5) {
      where.overallRating = { [Op.gte]: ratingFilter, [Op.lt]: ratingFilter + 1 };
    }
    if (ratingFields.includes(req.query.category)) {
      const minimum = Math.min(Math.max(Number.parseInt(req.query.minRating, 10) || 4, 1), 5);
      where[req.query.category] = { [Op.gte]: minimum };
    }
    if (req.query.withPhotos === 'true') {
      where[Op.and] = [sequelize.where(
        sequelize.cast(sequelize.col('Review.images'), 'TEXT'), { [Op.ne]: '[]' }
      )];
    }

    const { count, rows } = await Review.findAndCountAll({
      where,
      include: [
        { model: User, as: 'reviewer', attributes: ['fullName'] },
        { model: Booking, as: 'booking', attributes: ['checkOut'] }
      ],
      order,
      limit,
      offset: (page - 1) * limit
    });
    const published = await Review.findAll({
      where: { propertyId: property.id, status: 'published' },
      attributes: ['overallRating', ...ratingFields, 'title', 'comment']
    });
    res.json({
      reviews: rows.map(publicReview),
      summary: buildSummary(published),
      pagination: { page, limit, total: count, pages: Math.ceil(count / limit), sort }
    });
  } catch (error) {
    console.error('Get property reviews error:', error.message);
    res.status(500).json({ error: 'Failed to fetch reviews' });
  }
});

// Stays Agent: reviews of the agent's own properties only.
router.get('/agent', authenticateToken, requireRole('STAY_AGENT', 'RENTAL_AGENT'), async (req, res) => {
  try {
    const properties = await Property.findAll({
      where: { agentId: req.user.id, businessModel: 'bookable' },
      attributes: ['id', 'name', 'city', 'neighborhood']
    });
    const ids = properties.map((property) => property.id);
    const reviews = ids.length
      ? await Review.findAll({
        where: { propertyId: { [Op.in]: ids }, status: 'published' },
        include: [
          { model: User, as: 'reviewer', attributes: ['fullName'] },
          { model: Booking, as: 'booking', attributes: ['checkOut'] }
        ],
        order: [['createdAt', 'DESC']]
      })
      : [];
    res.json({
      properties: properties.map((property) => ({
        id: property.id,
        name: property.name,
        location: [property.neighborhood, property.city].filter(Boolean).join(', '),
        summary: buildSummary(reviews.filter((review) => review.propertyId === property.id))
      })),
      summary: buildSummary(reviews),
      reviews: reviews.map((review) => ({
        ...publicReview(review),
        propertyId: review.propertyId,
        propertyName: properties.find((property) => property.id === review.propertyId)?.name
      }))
    });
  } catch (error) {
    console.error('Get agent reviews error:', error.message);
    res.status(500).json({ error: 'Failed to fetch reviews' });
  }
});

// The only review field an agent may write; ratings and guest text stay immutable.
router.post('/:id/response', authenticateToken, requireRole('STAY_AGENT', 'RENTAL_AGENT'), [
  body('response').isString().trim().isLength({ min: 5, max: 1500 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'A response of 5 to 1500 characters is required' });
  }
  try {
    const review = await Review.findOne({
      where: { id: req.params.id, status: 'published' },
      include: [{ model: Property, as: 'property', attributes: ['agentId', 'name'] }]
    });
    if (!review || review.property?.agentId !== req.user.id) {
      return res.status(404).json({ error: 'Published review not found for your properties' });
    }
    await review.update({
      agentResponse: cleanedText(req.body.response, 1500),
      agentResponseAt: new Date(),
      agentResponderId: req.user.id
    });
    await notify(review.reviewerId, 'CUSTOMER', 'The host replied to your review',
      'The property team has responded to your review.', '/account/reviews', 'View review');
    res.json({ message: 'Response published', review: publicReview(review) });
  } catch (error) {
    console.error('Review response error:', error.message);
    res.status(500).json({ error: 'Failed to publish response' });
  }
});

router.post('/:id/reports', authenticateToken, requireRole('CUSTOMER', 'ADMIN', 'STAY_AGENT', 'RENTAL_AGENT'), [
  body('reason').trim().isLength({ min: 5, max: 1000 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'A report reason of 5 to 1000 characters is required' });
  }
  try {
    const review = await Review.findOne({
      where: { id: req.params.id, status: 'published' },
      include: [{ model: Property, as: 'property', attributes: ['agentId'] }]
    });
    if (!review) return res.status(404).json({ error: 'Published review not found' });
    if (review.reviewerId === req.user.id) {
      return res.status(403).json({ error: 'You cannot report your own review' });
    }
    if (req.user.role.endsWith('_AGENT') && review.property?.agentId !== req.user.id) {
      return res.status(403).json({ error: 'You can only report reviews of your own properties' });
    }
    await ReviewReport.create({
      reviewId: review.id,
      reporterId: req.user.id,
      reason: cleanedText(req.body.reason, 1000)
    });
    res.status(201).json({ message: 'Review reported for administrator review' });
  } catch (error) {
    if (error.name === 'SequelizeUniqueConstraintError') {
      return res.status(409).json({ error: 'You have already reported this review' });
    }
    console.error('Report review error:', error.message);
    res.status(500).json({ error: 'Failed to report review' });
  }
});

module.exports = router;
module.exports.reviewEligibility = reviewEligibility;
