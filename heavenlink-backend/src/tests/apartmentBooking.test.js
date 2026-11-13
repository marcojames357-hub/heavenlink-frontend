process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-apartment-booking-secret-32-characters';
process.env.OTP_SECRET = 'test-only-apartment-booking-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-apartment-booking-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { generateToken } = require('../middleware/auth');
const paymentService = require('../services/paymentService');
const {
  sequelize, syncDatabase, User, Property, RoomType, Booking, PaymentTransaction, UnlockRecord
} = require('../models');

let customer;
let otherCustomer;
let agent;
let admin;
let apartment;
let roomType;
let dates;
const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const createBooking = (user, key, overrides = {}) => request(app)
  .post('/api/v1/bookings').set(auth(user)).send({
    propertyId: apartment.id, requestKey: key, ...dates,
    guestName: user.fullName, guestCount: 2, ...overrides
  });
const availability = (overrides = {}) => request(app)
  .get('/api/v1/bookings/availability/check')
  .query({ propertyId: apartment.id, ...dates, ...overrides });

beforeAll(async () => {
  await syncDatabase();
  const createUser = (role, n) => User.create({
    fullName: `Test User ${n}`, email: `apartment-${n}@test.invalid`,
    phone: `+25570000200${n}`, password: 'test-password-123',
    role, verification: 'verified'
  });
  customer = await createUser('CUSTOMER', 1);
  otherCustomer = await createUser('CUSTOMER', 2);
  agent = await createUser('STAY_AGENT', 3);
  admin = await createUser('ADMIN', 4);
  apartment = await Property.create({
    name: 'Entire Apartment', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
    businessModel: 'bookable', category: 'shortStayApartment',
    imageUrl: 'https://example.invalid/a.jpg', bedrooms: 3, bathrooms: 2,
    description: 'A furnished apartment for booking tests.', managerName: 'Manager',
    listingStatus: 'published', agentId: agent.id
  });
  roomType = await RoomType.create({
    listingId: apartment.id, name: 'Entire unit', nightlyPriceTzs: 100000,
    capacity: 4, totalRooms: 3
  });
  const start = new Date(Date.now() + 10 * 86400000);
  const end = new Date(start.getTime() + 2 * 86400000);
  dates = { checkIn: start.toISOString(), checkOut: end.toISOString() };
}, 30000);

afterAll(async () => {
  jest.restoreAllMocks();
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('one apartment is one unit even when its room category claims multiple rooms', async () => {
  expect((await availability({ roomTypeId: roomType.id })).body).toMatchObject({
    available: true, availableRooms: 1
  });
  const results = await Promise.all([
    createBooking(customer, 'apartment-request-one', { roomTypeId: roomType.id }),
    createBooking(otherCustomer, 'apartment-request-two')
  ]);
  expect(results.map((result) => result.status).sort()).toEqual([201, 409]);
  expect((await availability()).body).toMatchObject({ available: false, availableRooms: 0 });
  expect((await availability({ roomTypeId: roomType.id })).body.available).toBe(false);
  const booking = await Booking.findOne({ where: { propertyId: apartment.id } });
  expect(booking.holdExpiresAt).not.toBeNull();
  await booking.update({ holdExpiresAt: new Date(Date.now() - 1000) });
  expect((await availability()).body.available).toBe(true);
});

test('booking request keys replay only identical requests by the same customer', async () => {
  const start = new Date(Date.now() + 90 * 86400000);
  const stay = {
    checkIn: start.toISOString(),
    checkOut: new Date(start.getTime() + 86400000).toISOString()
  };
  const responses = await Promise.all([
    createBooking(customer, 'apartment-idempotent', stay),
    createBooking(customer, 'apartment-idempotent', stay)
  ]);
  expect(responses.map((response) => response.status).sort()).toEqual([200, 201]);
  expect(responses[0].body.booking.id).toBe(responses[1].body.booking.id);
  expect(await Booking.count({ where: { requestKey: 'apartment-idempotent' } })).toBe(1);
  expect((await createBooking(customer, 'apartment-idempotent', { ...stay, guestCount: 3 })).status).toBe(409);
  expect((await createBooking(otherCustomer, 'apartment-idempotent', stay)).status).toBe(409);
});

test('adjacent bookings are allowed and cancelled bookings release their holds', async () => {
  const first = await createBooking(customer, 'apartment-current');
  expect(first.status).toBe(201);
  const adjacent = await createBooking(otherCustomer, 'apartment-adjacent', {
    checkIn: dates.checkOut,
    checkOut: new Date(new Date(dates.checkOut).getTime() + 86400000).toISOString()
  });
  expect(adjacent.status).toBe(201);
  const cancel = await request(app).post(`/api/v1/bookings/${first.body.booking.id}/cancel`).set(auth(customer));
  expect(cancel.status).toBe(200);
  expect((await availability()).body.available).toBe(true);
});

test('a late successful payment cannot revive a cancelled or expired apartment hold', async () => {
  const created = await createBooking(customer, 'apartment-expired-payment');
  expect(created.status).toBe(201);
  const booking = await Booking.findByPk(created.body.booking.id);
  const payment = await PaymentTransaction.create({
    reference: 'apartment-late-payment', purpose: 'accommodationBooking',
    amountTzs: booking.totalTzs, methodId: 'test', customerId: customer.id,
    bookingId: booking.id, status: 'pending'
  });
  await booking.update({
    paymentTransactionId: payment.id,
    holdExpiresAt: new Date(Date.now() - 1000)
  });
  jest.spyOn(paymentService, 'isConfigured').mockReturnValue(true);
  jest.spyOn(paymentService, 'verifyTransaction').mockImplementation(async () => {
    await payment.update({ status: 'succeeded', verifiedAt: new Date() });
    return payment;
  });
  const response = await request(app)
    .post(`/api/v1/payments/transactions/${payment.id}/verify`).set(auth(customer));
  expect(response.status).toBe(409);
  expect((await Booking.findByPk(booking.id)).status).toBe('pending');
  await booking.update({ status: 'cancelled' });
  expect((await request(app).post(`/api/v1/payments/transactions/${payment.id}/verify`)
    .set(auth(customer))).status).toBe(409);
});

test('booking confirmation cannot bypass verified payment processing', async () => {
  const booking = await Booking.findOne({ where: { requestKey: 'apartment-adjacent' } });
  const response = await request(app).patch(`/api/v1/bookings/${booking.id}/status`)
    .set(auth(agent)).send({ status: 'confirmed' });
  expect(response.status).toBe(403);
  expect((await Booking.findByPk(booking.id)).status).toBe('pending');
});

test('verified matching payment confirms an active hold once, but future stays cannot check out', async () => {
  const start = new Date(Date.now() + 30 * 86400000);
  const end = new Date(start.getTime() + 86400000);
  const created = await createBooking(customer, 'apartment-valid-payment', {
    checkIn: start.toISOString(), checkOut: end.toISOString()
  });
  expect(created.status).toBe(201);
  const booking = await Booking.findByPk(created.body.booking.id);
  const payment = await PaymentTransaction.create({
    reference: 'apartment-valid-payment', purpose: 'accommodationBooking',
    amountTzs: booking.totalTzs, methodId: 'test', customerId: customer.id,
    bookingId: booking.id, status: 'pending'
  });
  await booking.update({ paymentTransactionId: payment.id });
  paymentService.verifyTransaction.mockImplementation(async () => {
    await payment.update({ status: 'succeeded', verifiedAt: new Date() });
    return payment;
  });
  const verify = () => request(app).post(`/api/v1/payments/transactions/${payment.id}/verify`)
    .set(auth(customer));
  expect((await verify()).status).toBe(200);
  expect((await verify()).status).toBe(200);
  expect((await Booking.findByPk(booking.id)).status).toBe('confirmed');
  const earlyCheckout = await request(app).patch(`/api/v1/bookings/${booking.id}/status`)
    .set(auth(agent)).send({ status: 'completed' });
  expect(earlyCheckout.status).toBe(400);
  expect((await Booking.findByPk(booking.id)).checkedOutAt).toBeNull();
});

test('a failed superseded payment cannot cancel the current booking hold', async () => {
  const start = new Date(Date.now() + 60 * 86400000);
  const created = await createBooking(customer, 'apartment-superseded-payment', {
    checkIn: start.toISOString(),
    checkOut: new Date(start.getTime() + 86400000).toISOString()
  });
  expect(created.status).toBe(201);
  const booking = await Booking.findByPk(created.body.booking.id);
  const makePayment = (reference) => PaymentTransaction.create({
    reference, purpose: 'accommodationBooking', amountTzs: booking.totalTzs,
    methodId: 'test', customerId: customer.id, bookingId: booking.id, status: 'pending'
  });
  const oldPayment = await makePayment('old-apartment-payment');
  const currentPayment = await makePayment('current-apartment-payment');
  await booking.update({ paymentTransactionId: currentPayment.id });
  paymentService.verifyTransaction.mockImplementation(async (id) => {
    const payment = await PaymentTransaction.findByPk(id);
    await payment.update({ status: 'failed' });
    return payment;
  });
  const verify = (payment) => request(app)
    .post(`/api/v1/payments/transactions/${payment.id}/verify`).set(auth(customer));
  expect((await verify(oldPayment)).status).toBe(200);
  expect((await booking.reload()).status).toBe('pending');
  expect((await verify(currentPayment)).status).toBe(200);
  expect((await booking.reload()).status).toBe('cancelled');
});

test('reverification rejects a payment whose amount no longer matches a confirmed booking', async () => {
  const booking = await Booking.findOne({ where: { requestKey: 'apartment-valid-payment' } });
  const payment = await PaymentTransaction.findByPk(booking.paymentTransactionId);
  paymentService.verifyTransaction.mockImplementation(async () => payment);
  await payment.update({ amountTzs: booking.totalTzs - 1 });
  const response = await request(app)
    .post(`/api/v1/payments/transactions/${payment.id}/verify`).set(auth(customer));
  expect(response.status).toBe(409);
  await payment.update({ amountTzs: booking.totalTzs });
});

test('admin verification grants a rental unlock to the payment customer, not the admin', async () => {
  const listing = await Property.create({
    name: 'Rental test home', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
    businessModel: 'contactUnlock', category: 'house', imageUrl: 'https://example.invalid/rental.jpg',
    bedrooms: 1, bathrooms: 1, description: 'A rental home for payment verification.',
    managerName: 'Manager', listingStatus: 'published', agentId: agent.id
  });
  const payment = await PaymentTransaction.create({
    reference: 'admin-verifies-rental', purpose: 'rentalContactUnlock',
    amountTzs: 5000, methodId: 'test', customerId: customer.id,
    listingId: listing.id, status: 'pending'
  });
  paymentService.verifyTransaction.mockImplementation(async () => {
    await payment.update({ status: 'succeeded', verifiedAt: new Date() });
    return payment;
  });
  const response = await request(app)
    .post(`/api/v1/payments/transactions/${payment.id}/verify`).set(auth(admin));
  expect(response.status).toBe(200);
  expect(await UnlockRecord.count({ where: { listingId: listing.id, customerId: customer.id, status: 'active' } })).toBe(1);
  expect(await UnlockRecord.count({ where: { listingId: listing.id, customerId: admin.id } })).toBe(0);
});
