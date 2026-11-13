process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-haven-link-jwt-secret-32-characters';
process.env.OTP_SECRET = 'test-only-haven-link-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(),
  `haven-link-test-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const {
  sequelize, syncDatabase, User, Property, OwnerContact, PaymentTransaction,
  UnlockRecord, Booking, Review, AgentProfile, Notification
} = require('../models');
const { generateToken } = require('../middleware/auth');

let customer;
let rentalAgent;
let admin;
let listing;
let unpaidListing;
let contact;
let otherCustomer;
let stayListing;
let completedStay;
let secondCompletedStay;
let confirmedStay;
let createdReviewId;

beforeAll(async () => {
  await syncDatabase();
  customer = await User.create({
    fullName: 'Test Customer',
    email: 'customer@test.invalid',
    phone: '+255700000101',
    password: 'test-password-123',
    role: 'CUSTOMER',
    verification: 'verified'
  });
  rentalAgent = await User.create({
    fullName: 'Test Rental Agent',
    email: 'agent@test.invalid',
    phone: '+255700000102',
    password: 'test-password-123',
    role: 'RENTAL_AGENT',
    verification: 'verified'
  });
  admin = await User.create({
    fullName: 'Test Admin',
    email: 'admin@test.invalid',
    phone: '+255700000105',
    password: 'test-password-123',
    role: 'ADMIN',
    verification: 'verified'
  });
  listing = await Property.create({
    name: 'Test rental home',
    city: 'Dar es Salaam',
    neighborhood: 'Mbezi',
    priceTzs: 500000,
    businessModel: 'contactUnlock',
    category: 'house',
    imageUrl: 'https://example.invalid/home.jpg',
    bedrooms: 2,
    bathrooms: 1,
    description: 'A test home with enough description length.',
    latitude: -6.7,
    longitude: 39.2,
    formattedAddress: 'Private test address, Mbezi',
    managerName: 'Test Agent',
    listingStatus: 'published',
    agentId: rentalAgent.id
  });
  unpaidListing = await Property.create({
    name: 'Second test rental',
    city: 'Dar es Salaam',
    neighborhood: 'Sinza',
    priceTzs: 350000,
    businessModel: 'contactUnlock',
    category: 'room',
    imageUrl: 'https://example.invalid/room.jpg',
    bedrooms: 1,
    bathrooms: 1,
    description: 'A second test room with sufficient description length.',
    managerName: 'Test Agent',
    listingStatus: 'published',
    agentId: rentalAgent.id
  });
  contact = await OwnerContact.create({
    propertyId: listing.id,
    exactAddress: 'Plot 1, Private Road, Mbezi',
    contactName: 'Test Owner',
    role: 'Owner',
    phone: '+255700000103',
    whatsApp: '+255700000103',
    latitude: -6.7,
    longitude: 39.2
  });
  otherCustomer = await User.create({
    fullName: 'Other Customer',
    email: 'other-customer@test.invalid',
    phone: '+255700000106',
    password: 'test-password-123',
    role: 'CUSTOMER',
    verification: 'verified'
  });
  stayListing = await Property.create({
    name: 'Test verified stay',
    city: 'Dar es Salaam',
    neighborhood: 'Masaki',
    priceTzs: 150000,
    businessModel: 'bookable',
    category: 'hotel',
    imageUrl: 'https://example.invalid/stay.jpg',
    bedrooms: 1,
    bathrooms: 1,
    description: 'A verified accommodation for review tests.',
    managerName: 'Stay Manager',
    listingStatus: 'published',
    agentId: rentalAgent.id
  });
  completedStay = await Booking.create({
    propertyId: stayListing.id,
    requestKey: 'review-eligible-booking',
    customerId: customer.id,
    checkIn: new Date('2026-01-10T12:00:00.000Z'),
    checkOut: new Date('2026-01-12T10:00:00.000Z'),
    guestName: customer.fullName,
    subtotalTzs: 300000,
    feeTzs: 6000,
    totalTzs: 306000,
    status: 'completed'
  });
  secondCompletedStay = await Booking.create({
    propertyId: stayListing.id,
    requestKey: 'review-second-eligible-booking',
    customerId: otherCustomer.id,
    checkIn: new Date('2026-02-10T12:00:00.000Z'),
    checkOut: new Date('2026-02-11T10:00:00.000Z'),
    guestName: otherCustomer.fullName,
    subtotalTzs: 150000,
    feeTzs: 3000,
    totalTzs: 153000,
    status: 'completed'
  });
  confirmedStay = await Booking.create({
    propertyId: stayListing.id,
    requestKey: 'review-notification-booking',
    customerId: customer.id,
    checkIn: new Date('2026-01-15T12:00:00.000Z'),
    checkOut: new Date('2026-01-16T10:00:00.000Z'),
    guestName: customer.fullName,
    subtotalTzs: 150000,
    feeTzs: 3000,
    totalTzs: 153000,
    status: 'confirmed'
  });
}, 30000);

afterAll(async () => {
  await sequelize.close();
  try {
    fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
  } catch (_) {}
});

describe('listing contact security', () => {
  test('public rental responses omit protected contact and agent phone data', async () => {
    const response = await request(app).get('/api/v1/properties');
    expect(response.status).toBe(200);
    expect(response.body.properties.map((property) => property.id)).toContain(listing.id);
    for (const property of response.body.properties) {
      const serialized = JSON.stringify(property);
      expect(serialized).not.toContain(contact.phone);
      expect(serialized).not.toContain(contact.exactAddress);
      expect(property.contact).toBeUndefined();
      expect(property.agent).toBeUndefined();
      if (property.businessModel === 'contactUnlock') {
        expect(property.latitude).toBeUndefined();
        expect(property.longitude).toBeUndefined();
        expect(property.formattedAddress).toBeUndefined();
      }
    }
    const detail = await request(app).get(`/api/v1/properties/${listing.id}`);
    expect(detail.status).toBe(200);
    expect(detail.body.property.latitude).toBeUndefined();
  });

  test('stay information is public for stays, defaults sensibly and is unavailable for rentals', async () => {
    const stay = await request(app).get(`/api/v1/properties/${stayListing.id}/stay-info`);
    expect(stay.status).toBe(200);
    expect(stay.body.policy.checkInFrom).toBe('14:00');
    expect(stay.body.policy.checkOutBy).toBe('11:00');
    expect(Array.isArray(stay.body.roomTypes)).toBe(true);
    expect(JSON.stringify(stay.body)).not.toContain(contact.phone);

    const rental = await request(app).get(`/api/v1/properties/${listing.id}/stay-info`);
    expect(rental.status).toBe(404);
    const missing = await request(app).get('/api/v1/properties/00000000-0000-0000-0000-000000000000/stay-info');
    expect(missing.status).toBe(404);
  });

  test('agents can save valid coordinates but invalid or partial pins are rejected', async () => {
    const token = generateToken(rentalAgent);
    const invalid = await request(app)
      .put(`/api/v1/properties/${unpaidListing.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ latitude: 91, longitude: 39 });
    expect(invalid.status).toBe(400);

    const partial = await request(app)
      .put(`/api/v1/properties/${unpaidListing.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ latitude: -6.8 });
    expect(partial.status).toBe(400);

    const publishWithoutLocation = await request(app)
      .patch(`/api/v1/properties/${unpaidListing.id}/status`)
      .set('Authorization', `Bearer ${generateToken(admin)}`)
      .send({ status: 'published' });
    expect(publishWithoutLocation.status).toBe(400);

    const saved = await request(app)
      .put(`/api/v1/properties/${unpaidListing.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ latitude: -6.8, longitude: 39.1, formattedAddress: 'Sinza' });
    expect(saved.status).toBe(200);
    expect(saved.body.property.latitude).toBe(-6.8);
    expect(saved.body.property.locationVerification).toBe('pending');

    const contactUpdate = await request(app)
      .put(`/api/v1/properties/${listing.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ latitude: -6.9, longitude: 39.3, formattedAddress: 'Updated pin' });
    expect(contactUpdate.status).toBe(200);
    const updatedContact = await OwnerContact.findOne({
      where: { propertyId: listing.id }
    });
    expect(updatedContact.latitude).toBe(-6.9);
    expect(updatedContact.longitude).toBe(39.3);
  });

  test('contact details require an active unlock for this customer and listing', async () => {
    const token = generateToken(customer);
    const denied = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(denied.status).toBe(403);
    const hiddenLocation = await request(app)
      .get(`/api/v1/properties/${listing.id}/location`)
      .set('Authorization', `Bearer ${token}`);
    expect(hiddenLocation.status).toBe(403);

    const transaction = await PaymentTransaction.create({
      reference: 'TEST-UNLOCK-001',
      purpose: 'rentalContactUnlock',
      amountTzs: 5000,
      methodId: 'test',
      customerId: customer.id,
      listingId: listing.id,
      status: 'failed'
    });
    await UnlockRecord.create({
      customerId: customer.id,
      listingId: listing.id,
      paymentTransactionId: transaction.id,
      status: 'active',
      confirmedAt: new Date(),
      amountTzs: 5000
    });

    const failedPaymentContact = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(failedPaymentContact.status).toBe(403);
    const failedPaymentLocation = await request(app)
      .get(`/api/v1/properties/${listing.id}/location`)
      .set('Authorization', `Bearer ${token}`);
    expect(failedPaymentLocation.status).toBe(403);

    await transaction.update({ status: 'succeeded', verifiedAt: new Date() });

    const allowed = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(allowed.status).toBe(200);
    expect(allowed.body.contact.phone).toBe(contact.phone);
    const location = await request(app)
      .get(`/api/v1/properties/${listing.id}/location`)
      .set('Authorization', `Bearer ${token}`);
    expect(location.status).toBe(200);
    expect(location.body.location.latitude).toBe(-6.9);
  });

  test('while payments are unconfigured a customer opens rental details for free', async () => {
    const token = generateToken(otherCustomer);
    const before = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(before.status).toBe(403);

    const agentAttempt = await request(app)
      .post(`/api/v1/properties/${listing.id}/open-details`)
      .set('Authorization', `Bearer ${generateToken(rentalAgent)}`);
    expect(agentAttempt.status).toBe(403);
    const stayAttempt = await request(app)
      .post(`/api/v1/properties/${stayListing.id}/open-details`)
      .set('Authorization', `Bearer ${token}`);
    expect(stayAttempt.status).toBe(404);

    const opened = await request(app)
      .post(`/api/v1/properties/${listing.id}/open-details`)
      .set('Authorization', `Bearer ${token}`);
    expect(opened.status).toBe(201);
    const again = await request(app)
      .post(`/api/v1/properties/${listing.id}/open-details`)
      .set('Authorization', `Bearer ${token}`);
    expect(again.status).toBe(200);

    const contactResponse = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(contactResponse.status).toBe(200);
    const locationResponse = await request(app)
      .get(`/api/v1/properties/${listing.id}/location`)
      .set('Authorization', `Bearer ${token}`);
    expect(locationResponse.status).toBe(200);
  });

  test('unverified bookings do not grant access to guest messages', async () => {
    const owner = await request(app)
      .get(`/api/v1/agents/messages/${confirmedStay.id}`)
      .set('Authorization', `Bearer ${generateToken(customer)}`);
    expect(owner.status).toBe(403);

    const stranger = await request(app)
      .get(`/api/v1/agents/messages/${confirmedStay.id}`)
      .set('Authorization', `Bearer ${generateToken(otherCustomer)}`);
    expect(stranger.status).toBe(403);
  });

  test('rental inquiry endpoints are unavailable to customers and agents', async () => {
    const customerToken = generateToken(otherCustomer);
    const createInquiry = await request(app)
      .post(`/api/v1/properties/${listing.id}/inquiries`)
      .set('Authorization', `Bearer ${customerToken}`)
      .send({ message: 'Is this rental available?' });
    expect(createInquiry.status).toBe(404);

    const agentToken = generateToken(rentalAgent);
    const listInquiries = await request(app)
      .get('/api/v1/agents/inquiries')
      .set('Authorization', `Bearer ${agentToken}`);
    expect(listInquiries.status).toBe(404);

    const updateInquiry = await request(app)
      .put('/api/v1/agents/inquiries/not-an-inquiry')
      .set('Authorization', `Bearer ${agentToken}`)
      .send({ status: 'closed' });
    expect(updateInquiry.status).toBe(404);
  });

  test('rental agents cannot create stay listings by changing request fields', async () => {
    const token = generateToken(rentalAgent);
    const response = await request(app)
      .post('/api/v1/properties')
      .set('Authorization', `Bearer ${token}`)
      .send({
        name: 'Wrong portal listing',
        city: 'Arusha',
        neighborhood: 'Njiro',
        priceTzs: 100000,
        businessModel: 'bookable',
        category: 'hotel',
        imageUrl: 'https://example.invalid/hotel.jpg',
        bedrooms: 1,
        bathrooms: 1,
        description: 'A valid length description for this hotel.',
        managerName: 'Test Agent'
      });
    expect(response.status).toBe(403);
  });

  test('agents cannot self-verify ownership or skip listing moderation', async () => {
    const response = await request(app)
      .post('/api/v1/properties')
      .set('Authorization', `Bearer ${generateToken(rentalAgent)}`)
      .send({
        name: 'Unverified agent-submitted rental',
        city: 'Dar es Salaam',
        neighborhood: 'Ubungo',
        priceTzs: 250000,
        businessModel: 'contactUnlock',
        category: 'room',
        imageUrl: 'https://example.invalid/unverified-room.jpg',
        bedrooms: 1,
        bathrooms: 1,
        description: 'A valid length description for this rental room.',
        managerName: 'Test Agent',
        ownerVerification: 'verified',
        propertyVerification: 'verified',
        listingStatus: 'published',
        agentId: customer.id
      });
    expect(response.status).toBe(201);
    expect(response.body.property.ownerVerification).toBe('unverified');
    expect(response.body.property.propertyVerification).toBe('unverified');
    expect(response.body.property.listingStatus).toBe('pendingReview');
    expect(response.body.property.agentId).toBe(rentalAgent.id);
  });
});

test('payment endpoints never activate an unconfigured provider', async () => {
  const token = generateToken(customer);
  const response = await request(app)
    .post('/api/v1/payments/transactions')
    .set('Authorization', `Bearer ${token}`)
    .set('Idempotency-Key', 'test-unconfigured-transaction')
    .send({
      purpose: 'rentalContactUnlock',
      amountTzs: 5000,
      methodId: 'mpesa',
      listingId: unpaidListing.id
    });
  expect(response.status).toBe(503);
});

test('registration rejects an unverified or unrelated challenge', async () => {
  const response = await request(app)
    .post('/api/v1/auth/register')
    .send({
      fullName: 'Unverified User',
      email: 'unverified@test.invalid',
      phone: '+255700000104',
      password: 'test-password-123',
      role: 'RENTAL_AGENT',
      challengeId: '00000000-0000-4000-8000-000000000001',
      sessionId: 'test-session'
    });
  expect(response.status).toBe(403);
});

test('agent profiles persist profile fields and reject customer access', async () => {
  const token = generateToken(rentalAgent);
  const updated = await request(app)
    .put('/api/v1/agents/profile')
    .set('Authorization', `Bearer ${token}`)
    .send({
      displayName: 'Test Rental Agent',
      agencyName: 'Dar Homes',
      bio: 'Helping customers find verified rentals.',
      photoUrl: 'https://example.invalid/agent.jpg',
      videoUrl: 'https://example.invalid/intro.mp4',
      serviceAreas: ['Kinondoni', 'Ilala']
    });
  expect(updated.status).toBe(200);
  expect(updated.body.profile.agencyName).toBe('Dar Homes');
  expect(updated.body.profile.serviceAreas).toEqual(['Kinondoni', 'Ilala']);

  const persisted = await AgentProfile.findByPk(rentalAgent.id);
  expect(persisted.agencyName).toBe('Dar Homes');
  expect(persisted.photoUrl).toBe('https://example.invalid/agent.jpg');

  const read = await request(app)
    .get('/api/v1/agents/profile')
    .set('Authorization', `Bearer ${token}`);
  expect(read.status).toBe(200);
  expect(read.body.profile.bio).toBe('Helping customers find verified rentals.');

  const customerToken = generateToken(customer);
  const denied = await request(app)
    .get('/api/v1/agents/profile')
    .set('Authorization', `Bearer ${customerToken}`);
  expect(denied.status).toBe(403);
});

test('favorites persist once per customer and never expose contact data', async () => {
  const token = generateToken(customer);
  const url = `/api/v1/properties/${listing.id}/favorite`;
  const first = await request(app).put(url).set('Authorization', `Bearer ${token}`);
  const retry = await request(app).put(url).set('Authorization', `Bearer ${token}`);
  expect(first.status).toBe(200);
  expect(retry.status).toBe(200);

  const result = await request(app)
    .get('/api/v1/properties/favorites')
    .set('Authorization', `Bearer ${token}`);
  expect(result.status).toBe(200);
  expect(result.body.favorites).toHaveLength(1);
  expect(JSON.stringify(result.body.favorites)).not.toContain(contact.phone);

  const removed = await request(app)
    .delete(url)
    .set('Authorization', `Bearer ${token}`);
  expect(removed.status).toBe(200);
});

test('administrator fee updates persist and create audit events', async () => {
  const token = generateToken(admin);
  const update = await request(app)
    .put('/api/v1/admin/config')
    .set('Authorization', `Bearer ${token}`)
    .send({ unlockFeeTzs: 7000, bookingFeeRate: 0.03 });
  expect(update.status).toBe(200);

  const config = await request(app).get('/api/v1/payments/config');
  expect(config.body.config.unlockFeeTzs).toBe(7000);
  expect(config.body.config.bookingFeeRate).toBe(0.03);

  const audit = await request(app)
    .get('/api/v1/admin/audit-events')
    .set('Authorization', `Bearer ${token}`);
  expect(audit.status).toBe(200);
  expect(audit.body.events[0].action).toBe('BUSINESS_FEES_UPDATED');
});
test('a completed booking transition creates a customer review notification', async () => {
  const payment = await PaymentTransaction.create({
    reference: 'review-notification-payment',
    purpose: 'accommodationBooking',
    amountTzs: confirmedStay.totalTzs,
    methodId: 'test',
    customerId: confirmedStay.customerId,
    bookingId: confirmedStay.id,
    status: 'succeeded',
    verifiedAt: new Date()
  });
  await confirmedStay.update({ paymentTransactionId: payment.id });
  const completed = await request(app)
    .patch(`/api/v1/bookings/${confirmedStay.id}/status`)
    .set('Authorization', `Bearer ${generateToken(admin)}`)
    .send({ status: 'completed' });
  expect(completed.status).toBe(200);

  const notifications = await request(app)
    .get('/api/v1/agents/notifications')
    .set('Authorization', `Bearer ${generateToken(customer)}`);
  expect(notifications.status).toBe(200);
  expect(notifications.body.notifications).toEqual(expect.arrayContaining([
    expect.objectContaining({
      type: 'REVIEW_INVITATION',
      actionUrl: '/account/reviews'
    })
  ]));
  expect(notifications.body.notifications.filter((item) => item.type === 'REVIEW_INVITATION')).toHaveLength(1);

  const legacyBooking = await Booking.create({
    propertyId: stayListing.id, requestKey: 'unpaid-review-notification',
    customerId: customer.id, checkIn: new Date('2026-01-15T12:00:00.000Z'),
    checkOut: new Date('2026-01-16T10:00:00.000Z'), guestName: customer.fullName,
    subtotalTzs: 150000, feeTzs: 3000, totalTzs: 153000, status: 'confirmed'
  });
  const legacyCompletion = await request(app)
    .patch(`/api/v1/bookings/${legacyBooking.id}/status`)
    .set('Authorization', `Bearer ${generateToken(admin)}`)
    .send({ status: 'completed' });
  expect(legacyCompletion.status).toBe(200);
  expect(await Notification.count({
    where: { userId: customer.id, type: 'REVIEW_INVITATION' }
  })).toBe(1);
});

test('customer booking history loads its room associations without exposing another customer history', async () => {
  const response = await request(app).get('/api/v1/bookings')
    .set('Authorization', `Bearer ${generateToken(customer)}`);
  expect(response.status).toBe(200);
  expect(Array.isArray(response.body.bookings)).toBe(true);
  expect(response.body.bookings.length).toBeGreaterThan(0);
  for (const booking of response.body.bookings) {
    expect(booking.customerId).toBe(customer.id);
    expect(booking.property).toBeTruthy();
    expect(booking).toHaveProperty('roomType');
    expect(booking).toHaveProperty('assignedRoom');
  }
});
