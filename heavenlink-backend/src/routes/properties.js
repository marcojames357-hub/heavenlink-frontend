const express = require('express');
const workspaces = require('../services/workspaces');
const { body, validationResult } = require('express-validator');
const { Op, Transaction } = require('sequelize');
const {
  Property,
  OwnerContact,
  SavedProperty,
  UnlockRecord,
  PaymentTransaction,
  AdminAuditEvent,
  Review,
  Notification,
  CheckInPolicy,
  RoomType,
  Room,
  Booking,
  WalkInReservation,
  sequelize
} = require('../models');
const { authenticateToken, requireRole, requireVerifiedPhone } = require('../middleware/auth');
const paymentService = require('../services/paymentService');
const crypto = require('crypto');
const { acceptFiles, storeFiles, filePath } = require('../services/uploads');

const router = express.Router();

const stayRuleValidators = [
  body('maxGuests').optional({ nullable: true }).isInt({ min: 1, max: 50 }),
  body('stayRules').optional({ nullable: true }).isObject(),
  body('stayRules.minNights').optional({ nullable: true }).isInt({ min: 1, max: 365 }),
  body('stayRules.maxNights').optional({ nullable: true }).isInt({ min: 1, max: 365 })
    .custom((value, { req }) => value == null || req.body.stayRules?.minNights == null
      || Number(value) >= Number(req.body.stayRules.minNights))
    .withMessage('Maximum nights cannot be below minimum nights'),
  body('stayRules.checkInTime').optional({ nullable: true }).matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('stayRules.checkOutTime').optional({ nullable: true }).matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('stayRules.cancellationPolicy').optional({ nullable: true }).isString().trim().isLength({ max: 1000 }),
  body('stayRules.houseRules').optional({ nullable: true }).isString().trim().isLength({ max: 2000 }),
  body('stayRules.weekendPriceTzs').optional({ nullable: true }).isInt({ min: 0, max: 100000000 }),
  body('stayRules.cleaningFeeTzs').optional({ nullable: true }).isInt({ min: 0, max: 100000000 }),
  body('stayRules.beds').optional({ nullable: true }).isInt({ min: 1, max: 50 }),
  body('stayRules.country').optional({ nullable: true }).isString().trim().isLength({ max: 80 }),
  body('stayRules.region').optional({ nullable: true }).isString().trim().isLength({ max: 80 }),
  body('stayRules.photoLabels').optional({ nullable: true }).isObject()
    .custom((value) => Object.keys(value).length <= 13
      && Object.values(value).every((label) => typeof label === 'string' && label.length <= 40))
    .withMessage('Photo labels are invalid')
];
const APARTMENT_CATEGORIES = ['servicedApartment', 'shortStayApartment'];
// Capacity and booking rules belong to whole-unit apartments only.
const stripStayRules = (data, category) => {
  if (!APARTMENT_CATEGORIES.includes(category)) {
    delete data.maxGuests;
    delete data.stayRules;
  }
};

const isHotelInventory = (category, accommodationType) =>
  ['hotel', 'lodge'].includes(category) ||
  ['hotel', 'motel', 'lodge'].includes(accommodationType);
const validAccommodationType = (businessModel, category, accommodationType) =>
  !accommodationType || (businessModel === 'bookable' &&
    ((category === 'hotel' && ['hotel', 'motel'].includes(accommodationType)) ||
     (category === 'lodge' && accommodationType === 'lodge')));

const publicProperty = (property) => {
  const result = property.toJSON();
  if (result.accommodationType) result.category = result.accommodationType;
  if (result.businessModel === 'contactUnlock') {
    delete result.latitude;
    delete result.longitude;
    delete result.formattedAddress;
    delete result.locationVerification;
  } else if (result.locationVisibility !== 'exact') {
    delete result.latitude;
    delete result.longitude;
    delete result.formattedAddress;
  }
  return result;
};

const publishedRatingsFor = async (propertyIds) => {
  if (propertyIds.length === 0) return new Map();
  const rows = await Review.findAll({
    attributes: [
      'propertyId',
      [sequelize.fn('AVG', sequelize.col('overallRating')), 'averageRating'],
      [sequelize.fn('COUNT', sequelize.col('id')), 'publishedCount']
    ],
    where: { propertyId: { [Op.in]: propertyIds }, status: 'published' },
    group: ['propertyId'],
    raw: true
  });
  return new Map(rows.map((row) => [row.propertyId, row]));
};

const publicPropertyWithRatings = (property, ratings) => {
  const result = publicProperty(property);
  const aggregate = ratings.get(property.id);
  result.rating = aggregate ? Number(Number(aggregate.averageRating).toFixed(2)) : 0;
  result.reviewCount = Number(aggregate?.publishedCount ?? 0);
  return result;
};

const startingPricesFor = async (propertyIds) => {
  if (propertyIds.length === 0) return new Map();
  const rows = await RoomType.findAll({
    attributes: [
      'listingId',
      [sequelize.fn('MIN', sequelize.col('nightlyPriceTzs')), 'startingPriceTzs']
    ],
    where: { listingId: { [Op.in]: propertyIds } },
    group: ['listingId'],
    raw: true
  });
  return new Map(rows.map((row) => [row.listingId, Number(row.startingPriceTzs)]));
};

const logLocationChange = (req, property) => AdminAuditEvent.create({
  actorId: req.user.id,
  action: 'PROPERTY_LOCATION_UPDATED',
  entityType: 'Property',
  entityId: property.id,
  metadata: { locationVerification: property.locationVerification },
  ipAddress: req.ip
});

// Get all properties (public only for customers)
router.get('/', async (req, res) => {
  try {
    const { businessModel, city, category, minPrice, maxPrice } = req.query;
    
    const where = { listingStatus: 'published' };
    
    if (businessModel) where.businessModel = businessModel;
    if (city) where.city = city;
    if (category === 'motel') where.accommodationType = 'motel';
    else if (category === 'hotel') {
      where[Op.or] = [
        { accommodationType: 'hotel' },
        { accommodationType: null, category: 'hotel' }
      ];
    }
    else if (category) where.category = category;
    if (minPrice) where.priceTzs = { ...where.priceTzs, [Op.gte]: Number(minPrice) };
    if (maxPrice) where.priceTzs = { ...where.priceTzs, [Op.lte]: Number(maxPrice) };

    const properties = await Property.findAll({
      where,
      order: [['createdAt', 'DESC']]
    });

    const ids = properties.map((property) => property.id);
    const [ratings, startingPrices] = await Promise.all([
      publishedRatingsFor(ids),
      startingPricesFor(ids)
    ]);
    res.json({
      properties: properties.map((property) => {
        const result = publicPropertyWithRatings(property, ratings);
        if (startingPrices.has(property.id)) result.priceTzs = startingPrices.get(property.id);
        return result;
      })
    });
  } catch (error) {
    console.error('Get properties error:', error);
    res.status(500).json({ error: 'Failed to fetch properties' });
  }
});

// Listing photos are public marketing images, so they are served without a
// token. Content is validated by signature and files get random names.
router.post('/photos', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
  requireVerifiedPhone, acceptFiles('photos'), async (req, res) => {
    try {
      if (!req.files?.length) return res.status(400).json({ error: 'Choose at least one photo' });
      const names = await storeFiles(req.files, 'listing-photos', { allowPdf: false });
      const base = (process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`).replace(/\/$/, '');
      res.status(201).json({
        urls: names.map((name) => `${base}/api/v1/properties/photos/${name}`)
      });
    } catch (error) {
      if (error.status === 400) return res.status(400).json({ error: error.message });
      console.error('Upload listing photo error:', error);
      res.status(500).json({ error: 'Failed to upload photos' });
    }
  });

router.get('/photos/:name', (req, res) => {
  const target = filePath('listing-photos', req.params.name);
  if (!target || target.endsWith('.pdf')) return res.status(404).json({ error: 'Photo not found' });
  res.set('Cross-Origin-Resource-Policy', 'cross-origin');
  res.set('Cache-Control', 'public, max-age=86400');
  res.sendFile(target, (error) => {
    if (error && !res.headersSent) res.status(404).json({ error: 'Photo not found' });
  });
});

router.get('/favorites', authenticateToken, requireRole('CUSTOMER', 'ADMIN'), async (req, res) => {
  try {
    const favorites = await SavedProperty.findAll({
      where: { customerId: req.user.id },
      include: [{
        model: Property,
        as: 'property',
        attributes: [
          'id', 'name', 'city', 'neighborhood', 'priceTzs', 'businessModel',
          'category', 'imageUrl', 'imageUrls', 'listingStatus'
        ]
      }],
      order: [['createdAt', 'DESC']]
    });
    res.json({ favorites });
  } catch (error) {
    console.error('Get saved properties error:', error.message);
    res.status(500).json({ error: 'Failed to fetch saved properties' });
  }
});

router.put('/:id/favorite', authenticateToken, requireRole('CUSTOMER', 'ADMIN'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property || !property.isPublic()) {
      return res.status(404).json({ error: 'Public property not found' });
    }
    const [favorite] = await SavedProperty.findOrCreate({
      where: { customerId: req.user.id, listingId: property.id }
    });
    res.status(200).json({ favorite });
  } catch (error) {
    console.error('Save property error:', error.message);
    res.status(500).json({ error: 'Failed to save property' });
  }
});

router.delete('/:id/favorite', authenticateToken, requireRole('CUSTOMER', 'ADMIN'), async (req, res) => {
  try {
    await SavedProperty.destroy({
      where: { customerId: req.user.id, listingId: req.params.id }
    });
    res.json({ message: 'Property removed from saved properties' });
  } catch (error) {
    console.error('Remove saved property error:', error.message);
    res.status(500).json({ error: 'Failed to remove saved property' });
  }
});

// Get single property (public only)
router.get('/:id', async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);

    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (!property.isPublic()) {
      return res.status(403).json({ error: 'Property is not publicly available' });
    }

    const ratings = await publishedRatingsFor([property.id]);
    const startingPrices = await startingPricesFor([property.id]);
    const result = publicPropertyWithRatings(property, ratings);
    if (startingPrices.has(property.id)) result.priceTzs = startingPrices.get(property.id);
    res.json({ property: result });
  } catch (error) {
    console.error('Get property error:', error);
    res.status(500).json({ error: 'Failed to fetch property' });
  }
});

router.get('/:id/stay-info', async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property || !property.isPublic()) {
      return res.status(404).json({ error: 'Public property not found' });
    }
    if (property.businessModel !== 'bookable') {
      return res.status(404).json({ error: 'Stay information is only available for bookable stays' });
    }

    const [policy, roomTypes] = await Promise.all([
      CheckInPolicy.findOne({ where: { listingId: property.id } }),
      RoomType.findAll({ where: { listingId: property.id }, order: [['nightlyPriceTzs', 'ASC']] })
    ]);

    res.json({
      policy: {
        checkInFrom: policy?.checkInFrom || '14:00',
        checkOutBy: policy?.checkOutBy || '11:00',
        cancellationHours: policy?.cancellationHours ?? 24,
        allowLateCheckout: policy?.allowLateCheckout ?? false,
        notes: policy?.notes || ''
      },
      roomTypes: roomTypes.map((room) => ({
        id: room.id,
        name: room.name,
        nightlyPriceTzs: room.nightlyPriceTzs,
        currency: room.currency,
        capacity: room.capacity,
        totalRooms: room.totalRooms,
        amenities: Array.isArray(room.amenities) ? room.amenities : [],
        amenityDetails: Array.isArray(room.amenityDetails) ? room.amenityDetails : [],
        description: room.description || '',
        imageUrls: Array.isArray(room.imageUrls) ? room.imageUrls : [],
        primaryImageUrl: room.primaryImageUrl,
        bedType: room.bedType,
        numberOfBeds: room.numberOfBeds,
        bathroomType: room.bathroomType,
        sizeSqm: room.sizeSqm
      }))
    });
  } catch (error) {
    console.error('Get stay info error:', error);
    res.status(500).json({ error: 'Failed to fetch stay information' });
  }
});

// Early-stage access: while no payment provider is configured, a signed-in
// customer opens a rental's details for free. The access is recorded as a
// zero-amount unlock so the existing location/contact checks stay unchanged.
router.post('/:id/open-details', authenticateToken, requireRole('CUSTOMER'), async (req, res) => {
  try {
    if (paymentService.isConfigured()) {
      return res.status(402).json({ error: 'Payment is required to unlock this rental' });
    }
    const property = await Property.findByPk(req.params.id);
    if (!property || !property.isPublic() || property.businessModel !== 'contactUnlock') {
      return res.status(404).json({ error: 'Rental listing not found' });
    }
    let unlock = await UnlockRecord.findOne({
      where: { customerId: req.user.id, listingId: property.id }
    });
    if (unlock && unlock.status === 'active') {
      return res.json({ unlock });
    }
    const transaction = await PaymentTransaction.create({
      reference: `FREE-${crypto.randomBytes(8).toString('hex')}`,
      purpose: 'rentalContactUnlock',
      amountTzs: 0,
      methodId: 'free-preview',
      customerId: req.user.id,
      listingId: property.id,
      status: 'succeeded',
      verifiedAt: new Date()
    });
    if (unlock) {
      await unlock.update({
        status: 'active',
        confirmedAt: new Date(),
        paymentTransactionId: transaction.id,
        amountTzs: 0
      });
    } else {
      unlock = await UnlockRecord.create({
        customerId: req.user.id,
        listingId: property.id,
        paymentTransactionId: transaction.id,
        status: 'active',
        confirmedAt: new Date(),
        amountTzs: 0
      });
    }
    res.status(201).json({ unlock });
  } catch (error) {
    console.error('Open rental details error:', error.message);
    res.status(500).json({ error: 'Failed to open property details' });
  }
});

router.get('/:id/location', authenticateToken, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property || !property.isPublic()) {
      return res.status(404).json({ error: 'Public property not found' });
    }

    if (property.businessModel === 'contactUnlock') {
      const unlock = await UnlockRecord.findOne({
        where: {
          customerId: req.user.id,
          listingId: property.id,
          status: 'active'
        },
        include: [{
          model: PaymentTransaction,
          as: 'transaction',
          attributes: ['id', 'customerId', 'listingId', 'status']
        }]
      });
      const transaction = unlock?.transaction;
      if (!transaction || transaction.status !== 'succeeded' ||
          transaction.customerId !== req.user.id || transaction.listingId !== property.id) {
        return res.status(403).json({ error: 'Property location is locked' });
      }
    } else if (property.locationVisibility !== 'exact' && req.user.role !== 'ADMIN') {
      return res.status(403).json({ error: 'Exact property location is not public' });
    }

    if (property.latitude == null || property.longitude == null) {
      return res.status(404).json({ error: 'Property location is not available' });
    }

    res.json({
      location: {
        latitude: property.latitude,
        longitude: property.longitude,
        formattedAddress: property.formattedAddress
      }
    });
  } catch (error) {
    console.error('Get property location error:', error.message);
    res.status(500).json({ error: 'Failed to fetch property location' });
  }
});

// Get protected contact information (requires authentication and unlock)
router.get('/:id/contact', authenticateToken, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    if (property.businessModel !== 'contactUnlock') {
      return res.status(400).json({ error: 'This property does not use contact unlock' });
    }

    const unlock = await UnlockRecord.findOne({
      where: {
        customerId: req.user.id,
        listingId: property.id,
        status: 'active'
      },
      include: [{
        model: PaymentTransaction,
        as: 'transaction',
        attributes: ['id', 'customerId', 'listingId', 'status']
      }]
    });

    const transaction = unlock?.transaction;
    if (!transaction || transaction.status !== 'succeeded' ||
        transaction.customerId !== req.user.id || transaction.listingId !== property.id) {
      return res.status(403).json({ 
        error: 'Contact not unlocked',
        message: 'You must unlock this property to view contact information'
      });
    }

    const contact = await OwnerContact.findOne({
      where: { propertyId: property.id }
    });

    if (!contact) {
      return res.status(404).json({ error: 'Contact information not available' });
    }

    res.json({ contact });
  } catch (error) {
    console.error('Get contact error:', error);
    res.status(500).json({ error: 'Failed to fetch contact information' });
  }
});

// Create property (agents only)
router.post('/', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), requireVerifiedPhone, [
  body('name').trim().isLength({ min: 3, max: 200 }),
  body('city').trim().isLength({ min: 2, max: 100 }),
  body('neighborhood').trim().isLength({ min: 2, max: 100 }),
  body('priceTzs').isInt({ min: 0 }),
  body('businessModel').isIn(['bookable', 'contactUnlock']),
  body('category').isIn(['hotel', 'lodge', 'servicedApartment', 'shortStayApartment', 'house', 'room', 'sharedAccommodation']),
  body('imageUrl').isURL({ protocols: ['https'], require_protocol: true }),
  body('imageUrls').optional().isArray({ max: 12 }),
  body('imageUrls.*').optional().isURL({ protocols: ['https'], require_protocol: true }),
  body('latitude').optional({ nullable: true }).isFloat({ min: -90, max: 90 }),
  body('longitude').optional({ nullable: true }).isFloat({ min: -180, max: 180 }),
  body('accommodationType').optional().isIn(['hotel', 'motel', 'lodge']),
  body('formattedAddress').optional({ nullable: true }).isString().isLength({ max: 500 }),
  body('locationVisibility').optional().isIn(['exact', 'approximate', 'hidden']),
  body('bedrooms').isInt({ min: 0 }),
  body('bathrooms').isInt({ min: 0 }),
  ...stayRuleValidators,
  body('amenityDetails').optional().isArray({ max: 100 }),
  body('amenityDetails.*.name').isString().trim().isLength({ min: 1, max: 100 }),
  body('amenityDetails.*.description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 }),
  body('saveAsDraft').optional().isBoolean({ strict: true }),
  body('description').trim().isLength({ min: 10, max: 5000 }),
  body('managerName').trim().isLength({ min: 2, max: 100 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }
    if ((req.body.latitude == null) !== (req.body.longitude == null)) {
      return res.status(400).json({ error: 'Latitude and longitude must be provided together' });
    }

    const listingFields = [
      'name', 'city', 'neighborhood', 'priceTzs', 'businessModel', 'category',
      'accommodationType',
      'imageUrl', 'imageUrls', 'bedrooms', 'bathrooms', 'amenities', 'description',
      'amenityDetails',
      'available', 'furnished', 'parking', 'water', 'electricity', 'security',
      'managerName', 'rentalPeriod', 'latitude', 'longitude', 'formattedAddress',
      'locationVisibility', 'maxGuests', 'stayRules'
    ];
    const propertyData = Object.fromEntries(
      listingFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    stripStayRules(propertyData, propertyData.category);
    Object.assign(propertyData, {
      agentId: req.user.id,
      propertyVerification: 'unverified',
      ownerVerification: 'unverified',
      listingStatus: req.body.saveAsDraft === true ? 'draft' : 'pendingReview',
      locationVerification: propertyData.latitude == null ? 'unverified' : 'pending'
    });

    const capability = propertyData.businessModel === 'bookable'
      ? 'accommodationBooking'
      : 'rentalProperty';
    if (!req.user.hasCapability(capability)) {
      return res.status(403).json({ error: 'This account cannot manage this listing type' });
    }
    if (propertyData.businessModel === 'bookable'
      ? !['hotel', 'lodge', 'servicedApartment', 'shortStayApartment'].includes(propertyData.category)
      : !['house', 'room', 'sharedAccommodation'].includes(propertyData.category)) {
      return res.status(400).json({ error: 'Property type does not match the listing service' });
    }
    if (!validAccommodationType(propertyData.businessModel, propertyData.category, propertyData.accommodationType)) {
      return res.status(400).json({ error: 'Invalid multi-room accommodation type' });
    }

    const requiredWorkspace = workspaces.workspaceForProperty(propertyData);
    if (req.user.role !== 'ADMIN' && requiredWorkspace &&
        !(await workspaces.hasWorkspace(req.user, requiredWorkspace))) {
      return res.status(403).json({ error: 'Your account does not have access to this workspace', workspace: requiredWorkspace });
    }

    const property = await Property.create(propertyData);
    if (property.latitude != null) await logLocationChange(req, property);

    res.status(201).json({
      message: 'Property created successfully',
      property
    });
  } catch (error) {
    console.error('Create property error:', error);
    res.status(500).json({ error: 'Failed to create property' });
  }
});

// Update property (owner or admin only)
router.put('/:id', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), [
  ...stayRuleValidators,
  body('amenityDetails').optional().isArray({ max: 100 }),
  body('amenityDetails.*.name').isString().trim().isLength({ min: 1, max: 100 }),
  body('amenityDetails.*.description').optional({ nullable: true }).isString().trim().isLength({ max: 1000 }),
  body('latitude').optional({ nullable: true }).isFloat({ min: -90, max: 90 }),
  body('longitude').optional({ nullable: true }).isFloat({ min: -180, max: 180 }),
  body('accommodationType').optional({ nullable: true }).isIn(['hotel', 'motel', 'lodge']),
  body('formattedAddress').optional({ nullable: true }).isString().isLength({ max: 500 }),
  body('locationVisibility').optional().isIn(['exact', 'approximate', 'hidden'])
], async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    // Check ownership
    if ((property.agentId !== req.user.id && req.user.role !== 'ADMIN') ||
        (req.user.role !== 'ADMIN' && !req.user.hasCapability(
          property.businessModel === 'bookable' ? 'accommodationBooking' : 'rentalProperty'
        ))) {
      return res.status(403).json({ error: 'You do not have permission to update this property' });
    }

    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }
    if ((req.body.latitude == null) !== (req.body.longitude == null) &&
        (Object.hasOwn(req.body, 'latitude') || Object.hasOwn(req.body, 'longitude'))) {
      return res.status(400).json({ error: 'Latitude and longitude must be provided together' });
    }

    const editableFields = [
      'name', 'city', 'neighborhood', 'priceTzs', 'category', 'imageUrl',
      'accommodationType',
      'imageUrls', 'bedrooms', 'bathrooms', 'amenities', 'description',
      'amenityDetails',
      'available', 'furnished', 'parking', 'water', 'electricity', 'security',
      'managerName', 'rentalPeriod', 'latitude', 'longitude', 'formattedAddress',
      'locationVisibility', 'maxGuests', 'stayRules'
    ];
    const updates = Object.fromEntries(
      editableFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    stripStayRules(updates, updates.category ?? property.category);
    if (property.businessModel !== 'bookable') delete updates.locationVisibility;
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No editable listing fields provided' });
    }
    if (Object.hasOwn(updates, 'latitude') || Object.hasOwn(updates, 'longitude') ||
        Object.hasOwn(updates, 'formattedAddress')) {
      updates.locationVerification = 'pending';
    }
    await sequelize.transaction({ type: Transaction.TYPES.IMMEDIATE }, async (transaction) => {
      await property.reload({ transaction });
      const newCategory = updates.category ?? property.category;
      const validCategories = property.businessModel === 'bookable'
        ? ['hotel', 'lodge', 'servicedApartment', 'shortStayApartment']
        : ['house', 'room', 'sharedAccommodation'];
      if (!validCategories.includes(newCategory)) {
        const error = new Error('Property type does not match the listing service');
        error.status = 400;
        throw error;
      }
      if (Object.hasOwn(updates, 'category') && !Object.hasOwn(updates, 'accommodationType') &&
          updates.category !== property.category) updates.accommodationType = null;
      const newAccommodationType = Object.hasOwn(updates, 'accommodationType')
        ? updates.accommodationType : property.accommodationType;
      if (!validAccommodationType(property.businessModel, newCategory, newAccommodationType)) {
        const error = new Error('Invalid multi-room accommodation type');
        error.status = 400;
        throw error;
      }
      const changingInventory = property.businessModel === 'bookable' &&
        isHotelInventory(property.category, property.accommodationType) !==
        isHotelInventory(newCategory, newAccommodationType);
      if (changingInventory) {
        const [bookings, walkIns, rooms, types] = await Promise.all([
          Booking.count({ where: { propertyId: property.id }, transaction }),
          WalkInReservation.count({ where: { propertyId: property.id }, transaction }),
          Room.count({ where: { propertyId: property.id }, transaction }),
          RoomType.count({ where: { listingId: property.id }, transaction })
        ]);
        if (bookings || walkIns || rooms || types) {
          const error = new Error('Inventory model cannot change while booking history or room inventory exists. Contact support for review.');
          error.status = 409;
          throw error;
        }
        if (req.body.confirmInventoryModelChange !== true) {
          const error = new Error('Confirm the inventory model change before saving.');
          error.status = 409;
          throw error;
        }
        await AdminAuditEvent.create({
          actorId: req.user.id, action: 'PROPERTY_INVENTORY_MODEL_CHANGED',
          entityType: 'Property', entityId: property.id,
          metadata: { previousCategory: property.category, newCategory },
          ipAddress: req.ip
        }, { transaction });
      }
      await property.update(updates, { transaction });
    });
    if (Object.hasOwn(updates, 'latitude') && property.businessModel === 'contactUnlock') {
      await OwnerContact.update(
        { latitude: property.latitude, longitude: property.longitude },
        { where: { propertyId: property.id } }
      );
    }
    if (Object.hasOwn(updates, 'locationVerification')) await logLocationChange(req, property);

    res.json({
      message: 'Property updated successfully',
      property
    });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    console.error('Update property error:', error);
    res.status(500).json({ error: 'Failed to update property' });
  }
});

// Update property status (owner or admin only)
router.patch('/:id/status', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), [
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

    // Check ownership
    if ((property.agentId !== req.user.id && req.user.role !== 'ADMIN') ||
        (req.user.role !== 'ADMIN' && !req.user.hasCapability(
          property.businessModel === 'bookable' ? 'accommodationBooking' : 'rentalProperty'
        ))) {
      return res.status(403).json({ error: 'You do not have permission to update this property' });
    }

    if (req.body.status === 'published' &&
        (property.latitude == null || property.longitude == null)) {
      return res.status(400).json({ error: 'A confirmed property location is required before publishing' });
    }
    if (req.body.status === 'published' && property.businessModel === 'bookable' &&
        isHotelInventory(property.category, property.accommodationType)) {
      const [totalRooms, assignedRooms] = await Promise.all([
        Room.count({ where: { propertyId: property.id, status: 'active' } }),
        Room.count({ where: { propertyId: property.id, status: 'active', roomTypeId: { [Op.ne]: null } } })
      ]);
      if (totalRooms === 0 || totalRooms !== assignedRooms) {
        return res.status(400).json({
          error: 'Generate rooms and assign every active room to a category before publishing'
        });
      }
    }

    // Agents can only submit for review or pause their own listings
    if (req.user.role !== 'ADMIN') {
      const allowedStatuses = ['draft', 'pendingReview', 'paused'];
      if (!allowedStatuses.includes(req.body.status)) {
        return res.status(403).json({ error: 'Agents can only set status to draft, pending review, or paused' });
      }
    }

    await property.update({ listingStatus: req.body.status });

    res.json({
      message: 'Property status updated successfully',
      property
    });
  } catch (error) {
    console.error('Update property status error:', error);
    res.status(500).json({ error: 'Failed to update property status' });
  }
});

// Delete property (owner or admin only)
router.delete('/:id', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    // Check ownership
    if ((property.agentId !== req.user.id && req.user.role !== 'ADMIN') ||
        (req.user.role !== 'ADMIN' && !req.user.hasCapability(
          property.businessModel === 'bookable' ? 'accommodationBooking' : 'rentalProperty'
        ))) {
      return res.status(403).json({ error: 'You do not have permission to delete this property' });
    }

    await property.destroy();

    res.json({ message: 'Property deleted successfully' });
  } catch (error) {
    console.error('Delete property error:', error);
    res.status(500).json({ error: 'Failed to delete property' });
  }
});

// Report property (authenticated users)
router.post('/:id/report', authenticateToken, async (req, res) => {
  try {
    const property = await Property.findByPk(req.params.id);
    if (!property) {
      return res.status(404).json({ error: 'Property not found' });
    }

    await property.update({
      reportedCount: property.reportedCount + 1
    });

    res.json({ message: 'Property reported successfully' });
  } catch (error) {
    console.error('Report property error:', error);
    res.status(500).json({ error: 'Failed to report property' });
  }
});

// Set/update owner contact (property owner or admin only)
router.put('/:id/contact', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), [
  body('exactAddress').trim().isLength({ min: 5, max: 500 }),
  body('contactName').trim().isLength({ min: 2, max: 100 }),
  body('role').trim().isLength({ min: 2, max: 100 }),
  body('phone').matches(/^\+255\d{9}$/),
  body('whatsApp').matches(/^\+255\d{9}$/),
  body('latitude').isFloat({ min: -90, max: 90 }),
  body('longitude').isFloat({ min: -180, max: 180 })
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

    // Check ownership
    if ((property.agentId !== req.user.id && req.user.role !== 'ADMIN') ||
      (req.user.role !== 'ADMIN' && !req.user.hasCapability('rentalProperty'))) {
      return res.status(403).json({ error: 'You do not have permission to update this property' });
    }

    const contact = await OwnerContact.findOne({
      where: { propertyId: property.id }
    });

    const contactFields = [
      'exactAddress', 'contactName', 'role', 'phone', 'whatsApp', 'latitude', 'longitude'
    ];
    const contactUpdates = Object.fromEntries(
      contactFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    if (contact) {
      await contact.update(contactUpdates);
    } else {
      await OwnerContact.create({
        ...contactUpdates,
        propertyId: property.id
      });
    }
    await property.update({
      latitude: contactUpdates.latitude,
      longitude: contactUpdates.longitude,
      formattedAddress: contactUpdates.exactAddress,
      locationVerification: 'pending'
    });
    await logLocationChange(req, property);

    res.json({ message: 'Contact information updated successfully' });
  } catch (error) {
    console.error('Update contact error:', error);
    res.status(500).json({ error: 'Failed to update contact information' });
  }
});

module.exports = router;
