process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-workspace-secret-32-characters-long';
process.env.OTP_SECRET = 'test-only-workspace-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-workspaces-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { generateToken } = require('../middleware/auth');
const {
  sequelize, syncDatabase, User, Property, Booking, OtpChallenge, PaymentTransaction,
  Notification, RentObligation, RentReceipt, AgentWorkspace, BookingReceipt
} = require('../models');
const { onBookingConfirmed } = require('../services/bookingConfirmation');
const { runBookingReminders, runRentReminders } = require('../services/reminders');

const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const HOUR = 3600000;
let n = 0;
const makeUser = (role, extra = {}) => {
  n += 1;
  return User.create({
    fullName: `Workspace User ${n}`, email: `ws-${n}@test.invalid`, phone: `+25571000${String(n).padStart(4, '0')}`,
    password: 'test-password-123', role, verification: 'verified', ...extra
  });
};
const propertyBody = (overrides = {}) => ({
  name: 'Workspace Property', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
  businessModel: 'bookable', category: 'shortStayApartment',
  imageUrl: 'https://example.invalid/a.jpg', bedrooms: 3, bathrooms: 2,
  description: 'A furnished apartment for workspace tests.', managerName: 'Manager', ...overrides
});

async function register(role, workspaces) {
  n += 1;
  const phone = `+25572000${String(n).padStart(4, '0')}`;
  const sessionId = `session-${n}`;
  const challenge = await OtpChallenge.create({
    phoneE164: phone, sessionId, codeHash: 'x', expiresAt: new Date(Date.now() + 600000),
    resendAvailableAt: new Date(), verified: true
  });
  return request(app).post('/api/v1/auth/register').send({
    fullName: 'New Agent', email: `reg-${n}@test.invalid`, phone, password: 'test-password-123',
    role, workspaces, challengeId: challenge.id, sessionId
  });
}

beforeAll(async () => {
  await syncDatabase();
}, 30000);

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

describe('agent workspaces', () => {
  it('stores explicit workspace access at registration', async () => {
    const apartment = await register('STAY_AGENT', ['APARTMENT']);
    expect(apartment.status).toBe(201);
    expect(apartment.body.user.workspaces).toEqual([{ workspace: 'APARTMENT', status: 'active' }]);
    const rental = await register('RENTAL_AGENT', ['RENTAL']);
    expect(rental.body.user.role).toBe('RENTAL_AGENT');
    const mismatch = await register('RENTAL_AGENT', ['HOTEL']);
    expect(mismatch.status).toBe(400);
    const customer = await register('CUSTOMER', ['HOTEL']);
    expect(customer.status).toBe(400);
  });

  it('rejects property creation outside the agent workspace', async () => {
    const agent = (await register('STAY_AGENT', ['APARTMENT'])).body.user;
    const user = await User.findByPk(agent.id);
    const hotel = await request(app).post('/api/v1/properties').set(auth(user))
      .send(propertyBody({ category: 'hotel', accommodationType: 'hotel' }));
    expect(hotel.status).toBe(403);
    const apartment = await request(app).post('/api/v1/properties').set(auth(user)).send(propertyBody());
    expect(apartment.status).toBe(201);
    const walkIn = await request(app).get(`/api/v1/agents/walk-ins/${apartment.body.property.id}`).set(auth(user));
    expect(walkIn.status).toBe(403);
  });

  it('lets an agent add a second workspace and lists them', async () => {
    const agent = (await register('STAY_AGENT', ['APARTMENT'])).body.user;
    const user = await User.findByPk(agent.id);
    const added = await request(app).post('/api/v1/workspaces').set(auth(user)).send({ workspace: 'HOTEL' });
    expect(added.status).toBe(201);
    const hotel = await request(app).post('/api/v1/properties').set(auth(user))
      .send(propertyBody({ category: 'hotel', accommodationType: 'hotel' }));
    expect(hotel.status).toBe(201);
    const customer = await makeUser('CUSTOMER');
    expect((await request(app).get('/api/v1/workspaces').set(auth(customer))).status).toBe(403);
  });

  it('migrates legacy agents from their properties and flags ambiguous ones', async () => {
    const legacy = await makeUser('STAY_AGENT');
    await Property.create({ ...propertyBody(), agentId: legacy.id, listingStatus: 'published' });
    const listed = await request(app).get('/api/v1/workspaces').set(auth(legacy));
    expect(listed.body.workspaces).toEqual([
      { workspace: 'APARTMENT', status: 'active', source: 'legacyMigration' }
    ]);
    const ambiguous = await makeUser('STAY_AGENT');
    const blocked = await request(app).post('/api/v1/properties').set(auth(ambiguous)).send(propertyBody());
    expect(blocked.status).toBe(403);
    expect(await AgentWorkspace.count({ where: { userId: ambiguous.id, status: 'pending_review' } })).toBe(2);
    const confirmed = await request(app).post('/api/v1/workspaces').set(auth(ambiguous)).send({ workspace: 'APARTMENT' });
    expect(confirmed.status).toBe(201);
    expect((await request(app).post('/api/v1/properties').set(auth(ambiguous)).send(propertyBody())).status).toBe(201);
  });

  it('allows admins to revoke a workspace', async () => {
    const admin = await makeUser('ADMIN');
    const agent = (await register('STAY_AGENT', ['APARTMENT'])).body.user;
    const revoked = await request(app).patch(`/api/v1/workspaces/admin/${agent.id}/APARTMENT`)
      .set(auth(admin)).send({ status: 'revoked', reason: 'test' });
    expect(revoked.status).toBe(200);
    const user = await User.findByPk(agent.id);
    expect((await request(app).post('/api/v1/properties').set(auth(user)).send(propertyBody())).status).toBe(403);
    expect((await request(app).post('/api/v1/workspaces').set(auth(user)).send({ workspace: 'APARTMENT' })).status).toBe(403);
    const listed = await request(app).get(`/api/v1/workspaces/admin/${agent.id}`).set(auth(admin));
    expect(listed.status).toBe(200);
    expect(listed.body.workspaces).toEqual([
      expect.objectContaining({ workspace: 'APARTMENT', status: 'revoked' })
    ]);
    const customerAccount = await makeUser('CUSTOMER');
    expect((await request(app).get(`/api/v1/workspaces/admin/${customerAccount.id}`).set(auth(admin))).status).toBe(404);
    expect((await request(app).get(`/api/v1/workspaces/admin/${agent.id}`).set(auth(customerAccount))).status).toBe(403);
  });
});

describe('booking receipts and reminders', () => {
  let agent; let customer; let property; let booking;
  const now = new Date('2030-06-10T10:00:00.000Z');

  beforeAll(async () => {
    agent = await makeUser('STAY_AGENT');
    customer = await makeUser('CUSTOMER');
    property = await Property.create({
      ...propertyBody({ name: 'Coastal Suites' }), agentId: agent.id, listingStatus: 'published'
    });
    booking = await Booking.create({
      propertyId: property.id, customerId: customer.id, requestKey: 'reminder-booking',
      checkIn: new Date('2030-06-10T12:00:00.000Z'), checkOut: new Date('2030-06-11T08:00:00.000Z'),
      guestName: 'Guest One', subtotalTzs: 100000, feeTzs: 2000, totalTzs: 102000, status: 'pending'
    });
  });

  it('issues no receipt for unverified bookings and one receipt after verified payment', async () => {
    expect(await onBookingConfirmed(booking.id)).toBeNull();
    const payment = await PaymentTransaction.create({
      reference: 'PAY-RECEIPT-1', idempotencyKey: 'receipt-1', purpose: 'accommodationBooking',
      amountTzs: 102000, methodId: 'mobileMoney', customerId: customer.id, listingId: property.id,
      bookingId: booking.id, status: 'succeeded', verifiedAt: new Date()
    });
    await booking.update({ status: 'confirmed', paymentTransactionId: payment.id });
    const first = await onBookingConfirmed(booking.id);
    const second = await onBookingConfirmed(booking.id);
    expect(second.id).toBe(first.id);
    expect(await BookingReceipt.count({ where: { bookingId: booking.id } })).toBe(1);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'BOOKING_CONFIRMED' } })).toBe(1);
    const response = await request(app).get(`/api/v1/bookings/${booking.id}/receipt`).set(auth(customer));
    expect(response.status).toBe(200);
    expect(response.body.receipt).toMatchObject({ totalPaidTzs: 102000, transactionReference: 'PAY-RECEIPT-1' });
    const stranger = await makeUser('CUSTOMER');
    expect((await request(app).get(`/api/v1/bookings/${booking.id}/receipt`).set(auth(stranger))).status).toBe(404);
  });

  it('sends one check-in reminder inside the window and dedupes repeats', async () => {
    const before = new Date(Date.parse('2030-06-10T12:00:00.000Z') - 2 * HOUR - 3 * HOUR);
    await runBookingReminders(before);
    await runBookingReminders(before);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKIN_REMINDER' } })).toBe(1);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKOUT_ALERT_AGENT' } })).toBe(0);
  });

  it('sends customer and agent checkout alerts during the stay, and stops after cancellation', async () => {
    const during = new Date('2030-06-10T20:00:00.000Z');
    await runBookingReminders(during);
    await runBookingReminders(during);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKOUT_REMINDER', userId: customer.id } })).toBe(1);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKOUT_ALERT_AGENT', userId: agent.id } })).toBe(1);

    await booking.update({ checkOut: new Date('2030-06-12T08:00:00.000Z') });
    const later = new Date('2030-06-11T08:00:00.000Z');
    await runBookingReminders(later);
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKOUT_REMINDER' } })).toBe(2);

    await booking.update({ status: 'cancelled' });
    await runBookingReminders(new Date('2030-06-12T05:00:00.000Z'));
    expect(await Notification.count({ where: { bookingId: booking.id, type: 'CHECKOUT_DAY_REMINDER' } })).toBe(0);
  });

  it('does not make a stay review-eligible just because checkout time passed', async () => {
    const eligibility = await request(app).get(`/api/v1/reviews/eligibility/${booking.id}`).set(auth(customer));
    expect(eligibility.body.eligible).not.toBe(true);
  });
});

describe('rent reminders and notification center', () => {
  let agent; let tenant; let unlockCustomer; let property; let obligation;

  beforeAll(async () => {
    agent = await makeUser('RENTAL_AGENT', { capabilities: ['rentalProperty'] });
    tenant = await makeUser('CUSTOMER');
    unlockCustomer = await makeUser('CUSTOMER');
    property = await Property.create({
      ...propertyBody({ name: 'Rental House', businessModel: 'contactUnlock', category: 'house' }),
      agentId: agent.id, listingStatus: 'published'
    });
    obligation = await RentObligation.create({
      propertyId: property.id, unitReference: 'A02', billingMonth: '2030-07', expectedTzs: 300000,
      dueDate: '2030-07-13', createdById: agent.id
    });
  });

  const tenancyUrl = () => `/api/v1/finance/properties/${property.id}/rent/${obligation.id}/tenancy`;

  it('sends nothing until a verified tenant account is linked', async () => {
    expect(await runRentReminders(new Date('2030-07-06T09:00:00.000Z'))).toBe(0);
    const missing = await request(app).put(tenancyUrl()).set(auth(agent)).send({ tenantPhone: '+255700999999' });
    expect(missing.status).toBe(404);
    const linked = await request(app).put(tenancyUrl()).set(auth(agent)).send({ tenantPhone: tenant.phone });
    expect(linked.status).toBe(200);
    const other = await makeUser('RENTAL_AGENT', { capabilities: ['rentalProperty'] });
    expect((await request(app).put(tenancyUrl()).set(auth(other)).send({ endTenancy: true })).status).toBe(404);
  });

  it('reminds only the linked tenant on schedule without duplicates', async () => {
    const sevenDays = new Date('2030-07-06T09:00:00.000Z');
    await runRentReminders(sevenDays);
    await runRentReminders(sevenDays);
    expect(await Notification.count({ where: { userId: tenant.id, type: 'RENT_DUE' } })).toBe(1);
    expect(await Notification.count({ where: { userId: unlockCustomer.id } })).toBe(0);
    expect(await Notification.count({ where: { userId: agent.id, type: 'RENT_DUE_AGENT' } })).toBe(0);
  });

  it('mentions balances after partial payment and stops once settled or terminated', async () => {
    await RentReceipt.create({
      obligationId: obligation.id, amountTzs: 100000, paymentDate: '2030-07-08',
      createdById: agent.id, idempotencyKey: 'partial-1'
    });
    await runRentReminders(new Date('2030-07-10T09:00:00.000Z'));
    const partial = await Notification.findOne({ where: { userId: tenant.id, dedupeKey: `rent:${obligation.id}:2030-07-13:3` } });
    expect(partial.message).toContain('outstanding balance');
    expect(await Notification.count({ where: { userId: agent.id, type: 'RENT_DUE_AGENT' } })).toBe(1);

    await RentReceipt.create({
      obligationId: obligation.id, amountTzs: 200000, paymentDate: '2030-07-11',
      createdById: agent.id, idempotencyKey: 'partial-2'
    });
    await runRentReminders(new Date('2030-07-13T09:00:00.000Z'));
    await runRentReminders(new Date('2030-07-16T09:00:00.000Z'));
    expect(await Notification.count({ where: { userId: tenant.id, type: ['RENT_DUE', 'RENT_OVERDUE'] } })).toBe(2);
  });

  it('stops reminders after tenancy termination', async () => {
    const second = await RentObligation.create({
      propertyId: property.id, unitReference: 'A03', billingMonth: '2030-08', expectedTzs: 100000,
      dueDate: '2030-08-20', createdById: agent.id, tenantUserId: tenant.id
    });
    await request(app).put(`/api/v1/finance/properties/${property.id}/rent/${second.id}/tenancy`)
      .set(auth(agent)).send({ endTenancy: true });
    await runRentReminders(new Date('2030-08-17T09:00:00.000Z'));
    expect(await Notification.count({ where: { userId: tenant.id, dedupeKey: { [require('sequelize').Op.like]: `rent:${second.id}%` } } })).toBe(0);
  });

  it('exposes grouped notifications, read state, preferences and tenant statements', async () => {
    const grouped = await request(app).get('/api/v1/notifications?group=rent').set(auth(tenant));
    expect(grouped.status).toBe(200);
    expect(grouped.body.notifications.every((item) => item.category === 'rent')).toBe(true);
    const first = grouped.body.notifications[0];
    expect((await request(app).put(`/api/v1/notifications/${first.id}/read`).set(auth(unlockCustomer))).status).toBe(404);
    expect((await request(app).put(`/api/v1/notifications/${first.id}/read`).set(auth(tenant))).status).toBe(200);
    const count = await request(app).get('/api/v1/notifications/unread-count').set(auth(tenant));
    expect(count.body.unread).toBeGreaterThanOrEqual(0);
    const prefs = await request(app).put('/api/v1/notifications/preferences').set(auth(tenant))
      .send({ sms: false, mutedCategories: ['message'] });
    expect(prefs.body.preferences).toMatchObject({ sms: false, mutedCategories: ['message'] });
    const statements = await request(app).get('/api/v1/notifications/rental-statements').set(auth(tenant));
    expect(statements.body.statements.length).toBeGreaterThan(0);
    const none = await request(app).get('/api/v1/notifications/rental-statements').set(auth(unlockCustomer));
    expect(none.body.statements).toEqual([]);
  });
});
