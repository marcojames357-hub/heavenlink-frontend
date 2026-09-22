const express = require('express');
const { body, validationResult } = require('express-validator');
const { Op } = require('sequelize');
const { Property, OwnerContact, SavedProperty } = require('../models');
const { authenticateToken, requireRole, requireVerifiedPhone } = require('../middleware/auth');

const router = express.Router();

// Get all properties (public only for customers)
router.get('/', async (req, res) => {
  try {
    const { businessModel, city, category, minPrice, maxPrice } = req.query;

    const where = { listingStatus: 'published' };

    if (businessModel) where.businessModel = businessModel;
    if (city) where.city = city;
    if (category) where.category = category;
    if (minPrice) where.priceTzs = { ...where.priceTzs, [Op.gte]: Number(minPrice) };
    if (maxPrice) where.priceTzs = { ...where.priceTzs, [Op.lte]: Number(maxPrice) };

    const properties = await Property.findAll({
      where,
      order: [['createdAt', 'DESC']]
    });

    res.json({ properties });
  } catch (error) {
    console.error('Get properties error:', error);
    res.status(500).json({ error: 'Failed to fetch properties' });
  }
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

    res.json({ property });
  } catch (error) {
    console.error('Get property error:', error);
    res.status(500).json({ error: 'Failed to fetch property' });
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

    const { UnlockRecord } = require('../models');
    const unlock = await UnlockRecord.findOne({
      where: {
        customerId: req.user.id,
        listingId: property.id,
        status: 'active'
      }
    });

    if (!unlock) {
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
  body('bedrooms').isInt({ min: 0 }),
  body('bathrooms').isInt({ min: 0 }),
  body('description').trim().isLength({ min: 10, max: 5000 }),
  body('managerName').trim().isLength({ min: 2, max: 100 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const listingFields = [
      'name', 'city', 'neighborhood', 'priceTzs', 'businessModel', 'category',
      'imageUrl', 'imageUrls', 'bedrooms', 'bathrooms', 'amenities', 'description',
      'available', 'furnished', 'parking', 'water', 'electricity', 'security',
      'managerName', 'rentalPeriod'
    ];
    const propertyData = Object.fromEntries(
      listingFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    Object.assign(propertyData, {
      agentId: req.user.id,
      propertyVerification: 'unverified',
      ownerVerification: 'unverified',
      listingStatus: 'pendingReview'
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

    const property = await Property.create(propertyData);

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
router.put('/:id', authenticateToken, requireRole('RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'), async (req, res) => {
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

    const editableFields = [
      'name', 'city', 'neighborhood', 'priceTzs', 'category', 'imageUrl',
      'imageUrls', 'bedrooms', 'bathrooms', 'amenities', 'description',
      'available', 'furnished', 'parking', 'water', 'electricity', 'security',
      'managerName', 'rentalPeriod'
    ];
    const updates = Object.fromEntries(
      editableFields
        .filter((field) => Object.prototype.hasOwnProperty.call(req.body, field))
        .map((field) => [field, req.body[field]])
    );
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No editable listing fields provided' });
    }
    await property.update(updates);

    res.json({
      message: 'Property updated successfully',
      property
    });
  } catch (error) {
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

    res.json({ message: 'Contact information updated successfully' });
  } catch (error) {
    console.error('Update contact error:', error);
    res.status(500).json({ error: 'Failed to update contact information' });
  }
});

module.exports = router;
