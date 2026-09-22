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
const { sequelize, syncDatabase, User, Property, OwnerContact, PaymentTransaction, UnlockRecord } = require('../models');
const { generateToken } = require('../middleware/auth');

let customer;
let rentalAgent;
let admin;
let listing;
let unpaidListing;
let contact;

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
    }
  });

  test('contact details require an active unlock for this customer and listing', async () => {
    const token = generateToken(customer);
    const denied = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(denied.status).toBe(403);

    const transaction = await PaymentTransaction.create({
      reference: 'TEST-UNLOCK-001',
      purpose: 'rentalContactUnlock',
      amountTzs: 5000,
      methodId: 'test',
      customerId: customer.id,
      listingId: listing.id,
      status: 'succeeded',
      verifiedAt: new Date()
    });
    await UnlockRecord.create({
      customerId: customer.id,
      listingId: listing.id,
      paymentTransactionId: transaction.id,
      status: 'active',
      confirmedAt: new Date(),
      amountTzs: 5000
    });

    const allowed = await request(app)
      .get(`/api/v1/properties/${listing.id}/contact`)
      .set('Authorization', `Bearer ${token}`);
    expect(allowed.status).toBe(200);
    expect(allowed.body.contact.phone).toBe(contact.phone);
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
