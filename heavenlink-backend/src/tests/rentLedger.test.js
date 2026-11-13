process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-haven-link-jwt-secret-32-characters';
process.env.OTP_SECRET = 'test-only-haven-link-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-rent-test-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { sequelize, syncDatabase, User, Property } = require('../models');
const { generateToken } = require('../middleware/auth');
const { describeObligation } = require('../services/rentLedger');

let agent, otherAgent, customer, admin, rental, otherRental, stay;
const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const user = (name, role, number) => User.create({
  fullName: name, email: `${number}@rent.invalid`, phone: `+2557000010${number}`,
  password: 'test-password', role, verification: 'verified'
});
const property = (name, owner, model) => Property.create({
  name, city: 'Dar es Salaam', neighborhood: 'Sinza', priceTzs: 100000,
  businessModel: model, category: model === 'bookable' ? 'hotel' : 'house',
  imageUrl: 'https://example.invalid/property.jpg', bedrooms: 1, bathrooms: 1,
  description: 'Property for rent ledger testing.', managerName: 'Manager',
  agentId: owner.id
});
const pathFor = (p) => `/api/v1/finance/properties/${p.id}/rent`;
const payload = {
  unitReference: 'Unit 1', tenantReference: 'Tenant A', billingMonth: '2026-03',
  expectedTzs: 100000, dueDate: '2026-03-10'
};

beforeAll(async () => {
  await syncDatabase();
  agent = await user('Rental Agent', 'RENTAL_AGENT', '01');
  otherAgent = await user('Other Agent', 'RENTAL_AGENT', '02');
  customer = await user('Customer', 'CUSTOMER', '03');
  admin = await user('Administrator', 'ADMIN', '04');
  rental = await property('First rental', agent, 'contactUnlock');
  otherRental = await property('Other rental', otherAgent, 'contactUnlock');
  stay = await property('Stay property', agent, 'bookable');
});

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('requires authentication and property ownership; permits admin oversight', async () => {
  expect((await request(app).get(pathFor(rental))).status).toBe(401);
  expect((await request(app).get(pathFor(rental)).set(auth(customer))).status).toBe(403);
  expect((await request(app).get(pathFor(otherRental)).set(auth(agent))).status).toBe(404);
  expect((await request(app).post(pathFor(otherRental)).set(auth(agent)).send(payload)).status).toBe(404);
  expect((await request(app).post(pathFor(stay)).set(auth(agent)).send(payload)).status).toBe(404);
  expect((await request(app).get(pathFor(rental)).set(auth(admin))).status).toBe(200);
});

test('validates amount and dates and prevents duplicate unit-month records', async () => {
  for (const bad of [
    { expectedTzs: 1.5 }, { expectedTzs: -1 }, { expectedTzs: 1000000001 },
    { billingMonth: '2026-13' }, { dueDate: '2026-02-30' }, { unitReference: '  ' }
  ]) {
    const response = await request(app).post(pathFor(rental)).set(auth(agent)).send({ ...payload, ...bad });
    expect(response.status).toBe(400);
  }
  const created = await request(app).post(pathFor(rental)).set(auth(agent)).send(payload);
  expect(created.status).toBe(201);
  expect(created.body.record).toMatchObject({ expectedTzs: 100000, paidTzs: 0, outstandingTzs: 100000 });
  const duplicate = await request(app).post(pathFor(rental)).set(auth(agent)).send(payload);
  expect(duplicate.status).toBe(409);
});

test('records offline partial payments idempotently and rejects overpayment', async () => {
  const listing = await request(app).get(pathFor(rental)).set(auth(agent));
  const id = listing.body.records[0].id;
  const url = `${pathFor(rental)}/${id}/receipts`;
  const receipt = { amountTzs: 40000, paymentDate: '2026-03-05', idempotencyKey: 'receipt-1', reference: 'cash' };
  const created = await request(app).post(url).set(auth(agent)).send(receipt);
  expect(created.status).toBe(201);
  expect(created.body.receipt).toMatchObject({ source: 'manualOffline', platformVerified: false });
  const repeated = await request(app).post(url).set(auth(agent)).send(receipt);
  expect(repeated.status).toBe(200);
  expect(repeated.body.receipt.id).toBe(created.body.receipt.id);
  expect((await request(app).post(url).set(auth(agent)).send({ ...receipt, amountTzs: 1 })).status).toBe(409);
  expect((await request(app).post(url).set(auth(agent)).send({ ...receipt, idempotencyKey: 'receipt-2', amountTzs: 60001 })).status).toBe(409);
  const updated = await request(app).get(pathFor(rental)).set(auth(agent));
  expect(updated.body.records[0]).toMatchObject({ paidTzs: 40000, outstandingTzs: 60000, status: 'overdue' });

  const foreign = `${pathFor(otherRental)}/${id}/receipts/${created.body.receipt.id}/reverse`;
  expect((await request(app).post(foreign).set(auth(otherAgent)).send({ reason: 'Wrong receipt' })).status).toBe(404);
  const reverseUrl = `${url}/${created.body.receipt.id}/reverse`;
  expect((await request(app).post(reverseUrl).set(auth(agent)).send({ reason: 'Incorrect entry' })).status).toBe(200);
  expect((await request(app).post(reverseUrl).set(auth(agent)).send({ reason: 'Incorrect entry' })).status).toBe(409);
  const reversed = await request(app).get(pathFor(rental)).set(auth(agent));
  expect(reversed.body.records[0]).toMatchObject({ paidTzs: 0, outstandingTzs: 100000 });
  expect(reversed.body.records[0].receipts[0].reversalReason).toBe('Incorrect entry');
});

test('derives pending, partial, overdue and paid statuses from local due dates', () => {
  const obligation = { expectedTzs: 100, dueDate: '2026-03-10', toJSON: () => ({}) };
  const receipt = (amountTzs) => ({ amountTzs, reversedAt: null, toJSON: () => ({}) });
  expect(describeObligation(obligation, [], '2026-03-10').status).toBe('pending');
  expect(describeObligation(obligation, [receipt(10)], '2026-03-10').status).toBe('partiallyPaid');
  expect(describeObligation(obligation, [receipt(10)], '2026-03-11').status).toBe('overdue');
  expect(describeObligation(obligation, [receipt(100)], '2026-03-11').status).toBe('paid');
});

test('paginates and filters billing months', async () => {
  await request(app).post(pathFor(rental)).set(auth(agent)).send({
    ...payload, unitReference: 'Unit 2', billingMonth: '2026-04'
  });
  const filtered = await request(app).get(pathFor(rental)).query({ month: '2026-03', limit: 1 }).set(auth(agent));
  expect(filtered.status).toBe(200);
  expect(filtered.body.total).toBe(1);
  expect(filtered.body.records).toHaveLength(1);
  expect(filtered.body.records[0].unitReference).toBe('Unit 1');
  expect((await request(app).get(pathFor(rental)).query({ limit: 101 }).set(auth(agent))).status).toBe(400);
});
