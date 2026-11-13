process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-booking-messaging-secret-32-characters';
process.env.OTP_SECRET = 'test-only-booking-messaging-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-messaging-test-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { generateToken } = require('../middleware/auth');
const {
  sequelize, syncDatabase, User, Property, Booking, PaymentTransaction,
  GuestMessage, Notification
} = require('../models');

let customer;
let otherCustomer;
let agent;
let otherAgent;
let admin;
let property;
let booking;
let payment;
const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const getMessages = (user) => request(app).get(`/api/v1/agents/messages/${booking.id}`).set(auth(user));
const sendMessage = (user) => request(app).post('/api/v1/agents/messages').set(auth(user))
  .send({ bookingId: booking.id, body: 'Hello about the stay.' });

beforeAll(async () => {
  await syncDatabase();
  const createUser = (role, n) => User.create({
    fullName: `Test User ${n}`, email: `message-${n}@test.invalid`,
    phone: `+25570000100${n}`, password: 'test-password-123',
    role, verification: 'verified'
  });
  customer = await createUser('CUSTOMER', 1);
  otherCustomer = await createUser('CUSTOMER', 2);
  agent = await createUser('STAY_AGENT', 3);
  otherAgent = await createUser('STAY_AGENT', 4);
  admin = await createUser('ADMIN', 5);
  property = await Property.create({
    name: 'Test Hotel', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
    businessModel: 'bookable', category: 'hotel', imageUrl: 'https://example.invalid/a.jpg',
    bedrooms: 1, bathrooms: 1, description: 'A test stay for guest messaging.',
    managerName: 'Manager', listingStatus: 'published', agentId: agent.id
  });
  booking = await Booking.create({
    propertyId: property.id, customerId: customer.id,
    checkIn: new Date('2026-01-01'), checkOut: new Date('2026-01-03'),
    guestName: 'Test Customer', subtotalTzs: 200000, feeTzs: 0, totalTzs: 200000
  });
  payment = await PaymentTransaction.create({
    reference: 'test-booking-message-payment', purpose: 'accommodationBooking',
    amountTzs: booking.totalTzs, methodId: 'test', customerId: customer.id,
    bookingId: booking.id, status: 'pending'
  });
  await booking.update({ paymentTransactionId: payment.id });
}, 30000);

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('pending, unverified, failed and mismatched payments cannot authorize messaging', async () => {
  expect((await getMessages(customer)).status).toBe(403);
  expect((await sendMessage(customer)).status).toBe(403);
  await booking.update({ status: 'confirmed' });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ status: 'failed', verifiedAt: new Date() });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ status: 'succeeded', verifiedAt: null });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ verifiedAt: new Date() });
  await payment.update({ status: 'succeeded', amountTzs: 1 });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ amountTzs: booking.totalTzs, customerId: otherCustomer.id });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ customerId: customer.id, bookingId: null });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ bookingId: booking.id, purpose: 'rentalContactUnlock' });
  expect((await sendMessage(customer)).status).toBe(403);
  await payment.update({ purpose: 'accommodationBooking' });
  expect(await GuestMessage.count()).toBe(0);
});

test('rental listings cannot use stay booking conversations', async () => {
  await property.update({ businessModel: 'contactUnlock' });
  expect((await getMessages(customer)).status).toBe(403);
  expect((await sendMessage(customer)).status).toBe(403);
  await property.update({ businessModel: 'bookable' });
});

test('only the booking customer and property agent may read and send', async () => {
  for (const user of [otherCustomer, otherAgent, admin]) {
    expect((await getMessages(user)).status).toBe(403);
    expect((await sendMessage(user)).status).toBe(403);
  }
  expect((await sendMessage(customer)).status).toBe(201);
  expect((await sendMessage(agent)).status).toBe(201);
  expect((await getMessages(customer)).body.messages).toHaveLength(2);
  expect((await getMessages(agent)).body.messages).toHaveLength(2);
  expect(await Notification.count({ where: { userId: agent.id } })).toBe(1);
  expect(await Notification.count({ where: { userId: customer.id } })).toBe(1);
});

test('cancelled or refunded bookings preserve history but prohibit new messages', async () => {
  await booking.update({ status: 'cancelled' });
  await payment.update({ status: 'refunded' });
  expect((await getMessages(customer)).status).toBe(200);
  expect((await getMessages(agent)).status).toBe(200);
  expect((await sendMessage(customer)).status).toBe(403);
  expect((await sendMessage(agent)).status).toBe(403);
});

test('completed bookings allow messaging for 14 days after recorded checkout', async () => {
  await payment.update({ status: 'succeeded' });
  await booking.update({ status: 'completed', checkedOutAt: new Date() });
  expect((await sendMessage(customer)).status).toBe(201);
  await booking.update({ checkedOutAt: new Date(Date.now() - 15 * 86400000) });
  expect((await sendMessage(customer)).status).toBe(403);
  expect((await getMessages(customer)).status).toBe(200);
  await booking.update({ checkedOutAt: null });
  expect((await sendMessage(customer)).status).toBe(403);
});
