process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-rental-messaging-secret-32-characters';
process.env.OTP_SECRET = 'test-only-rental-messaging-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-rental-messaging-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { generateToken } = require('../middleware/auth');
const {
  sequelize, syncDatabase, User, Property, PaymentTransaction, UnlockRecord, RentalMessage
} = require('../models');

const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const getMessages = (user, listingId, customerId) =>
  request(app).get(`/api/v1/agents/rental-messages/${listingId}/${customerId}`).set(auth(user));
const sendMessage = (user, listingId, customerId) =>
  request(app).post('/api/v1/agents/rental-messages').set(auth(user))
    .send({ listingId, customerId, body: 'Can I arrange a viewing?' });

let customer;
let otherCustomer;
let agent;
let otherAgent;
let listing;
let otherListing;
let unlock;
let payment;

beforeAll(async () => {
  await syncDatabase();
  const createUser = (role, n) => User.create({
    fullName: `Rental Chat User ${n}`,
    email: `rental-chat-${n}@test.invalid`,
    phone: `+25570000200${n}`,
    password: 'test-password-123',
    role,
    verification: 'verified'
  });
  [customer, otherCustomer, agent, otherAgent] = await Promise.all([
    createUser('CUSTOMER', 1),
    createUser('CUSTOMER', 2),
    createUser('RENTAL_AGENT', 3),
    createUser('RENTAL_AGENT', 4)
  ]);
  const createListing = (name, owner) => Property.create({
    name,
    city: 'Dar es Salaam',
    neighborhood: 'Mbezi',
    priceTzs: 400000,
    businessModel: 'contactUnlock',
    category: 'house',
    imageUrl: 'https://example.invalid/rental.jpg',
    bedrooms: 2,
    bathrooms: 1,
    description: 'A rental listing used to test listing-scoped messages.',
    managerName: owner.fullName,
    listingStatus: 'published',
    agentId: owner.id
  });
  [listing, otherListing] = await Promise.all([
    createListing('Rental chat home', agent),
    createListing('Other rental', agent)
  ]);
}, 30000);

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('rental conversations require a verified unlock for the same customer and listing', async () => {
  expect((await sendMessage(customer, listing.id, customer.id)).status).toBe(403);

  payment = await PaymentTransaction.create({
    reference: 'rental-chat-unverified-payment',
    purpose: 'rentalContactUnlock',
    amountTzs: 5000,
    methodId: 'test',
    customerId: customer.id,
    listingId: listing.id,
    status: 'pending'
  });
  unlock = await UnlockRecord.create({
    customerId: customer.id,
    listingId: listing.id,
    paymentTransactionId: payment.id,
    status: 'active',
    amountTzs: 5000
  });
  expect((await sendMessage(customer, listing.id, customer.id)).status).toBe(403);

  await payment.update({ status: 'succeeded', verifiedAt: new Date() });
  expect((await sendMessage(customer, otherListing.id, customer.id)).status).toBe(403);
  expect((await sendMessage(otherCustomer, listing.id, otherCustomer.id)).status).toBe(403);
  expect((await sendMessage(otherAgent, listing.id, customer.id)).status).toBe(403);
});

test('only the customer and owner can read or send messages after unlock', async () => {
  expect((await getMessages(customer, listing.id, customer.id)).status).toBe(200);
  expect((await getMessages(agent, listing.id, customer.id)).status).toBe(200);
  expect((await sendMessage(customer, listing.id, customer.id)).status).toBe(201);
  const agentReply = await request(app).post('/api/v1/agents/rental-messages')
    .set(auth(agent))
    .send({ listingId: listing.id, customerId: customer.id, body: 'Yes, please contact us.' });
  expect(agentReply.status).toBe(201);
  expect((await getMessages(otherCustomer, listing.id, customer.id)).status).toBe(403);
  expect((await getMessages(otherAgent, listing.id, customer.id)).status).toBe(403);
  expect(await RentalMessage.count({
    where: { listingId: listing.id, customerId: customer.id }
  })).toBe(2);
});

test('rental agent inbox is limited to unlocked conversations for owned listings', async () => {
  const response = await request(app).get('/api/v1/agents/rental-conversations').set(auth(agent));
  expect(response.status).toBe(200);
  expect(response.body.conversations).toEqual(expect.arrayContaining([
    expect.objectContaining({ listingId: listing.id, customerId: customer.id })
  ]));
  expect(response.body.conversations.some((item) => item.listingId === otherListing.id)).toBe(false);
  expect((await request(app).get('/api/v1/agents/rental-conversations').set(auth(otherAgent))).body.conversations).toEqual([]);
});

test('refund or unlock revocation blocks new access while preserving messages', async () => {
  await unlock.update({ status: 'refunded' });
  expect((await getMessages(customer, listing.id, customer.id)).status).toBe(403);
  expect((await sendMessage(agent, listing.id, customer.id)).status).toBe(403);
  expect(await RentalMessage.count({
    where: { listingId: listing.id, customerId: customer.id }
  })).toBe(2);
});
