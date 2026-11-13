process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-haven-link-jwt-secret-32-characters';
process.env.OTP_SECRET = 'test-only-haven-link-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-finance-test-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const {
  sequelize, syncDatabase, User, Property, Booking, PaymentTransaction,
  FinancialAlert, Notification, AdminAuditEvent
} = require('../models');
const { generateToken } = require('../middleware/auth');
const { refreshPropertyAlerts } = require('../services/financialManagement');

let rentalAgent, stayAgent, otherAgent, customer, admin, rental, stay, otherRental;
const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const user = (name, role, number) => User.create({
  fullName: name, email: `${number}@finance.invalid`, phone: `+2557000020${number}`,
  password: 'test-password', role, verification: 'verified'
});
const property = (name, owner, model) => Property.create({
  name, city: 'Dar es Salaam', neighborhood: 'Sinza', priceTzs: 100000,
  businessModel: model, category: model === 'bookable' ? 'hotel' : 'house',
  imageUrl: 'https://example.invalid/property.jpg', bedrooms: 1, bathrooms: 1,
  description: 'Property for finance management tests.', managerName: 'Manager',
  agentId: owner.id
});
const p = (item, path) => `/api/v1/finance/properties/${item.id}/${path}`;

beforeAll(async () => {
  await syncDatabase();
  rentalAgent = await user('Rental Agent', 'RENTAL_AGENT', '01');
  stayAgent = await user('Stay Agent', 'STAY_AGENT', '02');
  otherAgent = await user('Other Rental Agent', 'RENTAL_AGENT', '03');
  customer = await user('Customer', 'CUSTOMER', '04');
  admin = await user('Admin', 'ADMIN', '05');
  rental = await property('Managed rental', rentalAgent, 'contactUnlock');
  stay = await property('Managed stay', stayAgent, 'bookable');
  otherRental = await property('Other rental', otherAgent, 'contactUnlock');
});

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('records expenses, utilities and optional staff payments without trusting client totals', async () => {
  const expenseResponse = await request(app).post(p(rental, 'expenses')).set(auth(rentalAgent)).send({
    title: 'Roof repair', category: 'maintenance', amountTzs: 50000, expenseDate: '2026-03-01',
    paidTzs: 50000, reversedAt: '2026-03-02', createdById: customer.id
  });
  expect(expenseResponse.status).toBe(201);
  expect(expenseResponse.body.record).toMatchObject({ amountTzs: 50000, paidTzs: 0 });
  expect(expenseResponse.body.record.createdById).toBe(rentalAgent.id);

  const bill = await request(app).post(p(rental, 'bills')).set(auth(rentalAgent)).send({
    category: 'electricity', provider: 'LUKU', billingMonth: '2026-03',
    amountTzs: 20000, dueDate: '2026-03-10', recurring: true, paidTzs: 20000
  });
  expect(bill.status).toBe(201);
  expect(bill.body.record.paidTzs).toBe(0);
  const staff = await request(app).post(p(rental, 'staff')).set(auth(rentalAgent)).send({
    staffName: 'Asha', staffRole: 'Caretaker', frequency: 'monthly',
    amountTzs: 30000, dueDate: '2026-03-31'
  });
  expect(staff.status).toBe(201);

  const dashboard = await request(app).get('/api/v1/finance/dashboard')
    .query({ businessModel: 'contactUnlock', propertyId: rental.id }).set(auth(rentalAgent));
  expect(dashboard.status).toBe(200);
  expect(dashboard.body.summary).toMatchObject({
    expenseTzs: 100000, staffObligationsTzs: 30000, utilityBillsOutstandingTzs: 20000,
    operatingProfitTzs: -100000
  });
  expect(dashboard.body.properties).toEqual([{ id: rental.id, name: rental.name }]);
  expect((await request(app).get('/api/v1/finance/dashboard')
    .query({ businessModel: 'bookable' }).set(auth(rentalAgent))).status).toBe(403);
});

test('records offline payments idempotently and audits reversals', async () => {
  const expense = await request(app).post(p(rental, 'expenses')).set(auth(rentalAgent)).send({
    title: 'Gate repair', category: 'maintenance', amountTzs: 15000, expenseDate: '2026-03-02'
  });
  const id = expense.body.record.id;
  const url = p(rental, `propertyExpense/${id}/payments`);
  const payment = {
    amountTzs: 5000, paymentDate: '2026-03-03', method: 'cash',
    reference: 'R-1', idempotencyKey: 'offline-payment-1'
  };
  const created = await request(app).post(url).set(auth(rentalAgent)).send(payment);
  expect(created.status).toBe(201);
  expect(created.body.payment).toMatchObject({ source: 'manualOffline', platformVerified: false });
  expect((await request(app).post(url).set(auth(rentalAgent)).send(payment)).status).toBe(200);
  expect((await request(app).post(url).set(auth(rentalAgent))
    .send({ ...payment, amountTzs: 6000 })).status).toBe(409);

  const reverseUrl = p(rental, `payments/${created.body.payment.id}/reverse`);
  expect((await request(app).post(reverseUrl).set(auth(otherAgent))
    .send({ reason: 'Wrong property' })).status).toBe(404);
  const reverseExpenseUrl = p(rental, `expenses/${id}/reverse`);
  expect((await request(app).post(reverseExpenseUrl).set(auth(rentalAgent))
    .send({ reason: 'Recorded in error' })).status).toBe(409);
  expect((await request(app).post(reverseUrl).set(auth(rentalAgent))
    .send({ reason: 'Recorded in error' })).status).toBe(200);
  expect((await request(app).post(reverseUrl).set(auth(rentalAgent))
    .send({ reason: 'Recorded in error' })).status).toBe(409);
  expect((await request(app).post(reverseExpenseUrl).set(auth(rentalAgent))
    .send({ reason: 'Recorded in error' })).status).toBe(200);
  expect((await request(app).post(reverseExpenseUrl).set(auth(rentalAgent))
    .send({ reason: 'Recorded in error' })).status).toBe(409);
  expect(await AdminAuditEvent.count({ where: { entityType: 'FinancialPayment' } })).toBeGreaterThan(0);
});

test('reports rent collections by receipt date and keeps operating profit separate from cash flow', async () => {
  const obligation = await request(app).post(p(rental, 'rent')).set(auth(rentalAgent)).send({
    unitReference: 'cash-basis-test', billingMonth: '2026-03',
    expectedTzs: 80000, dueDate: '2026-03-05'
  });
  expect(obligation.status).toBe(201);
  const receipt = await request(app).post(p(rental, `rent/${obligation.body.record.id}/receipts`))
    .set(auth(rentalAgent)).send({
      amountTzs: 20000, paymentDate: '2026-04-10', idempotencyKey: 'cash-basis-april'
    });
  expect(receipt.status).toBe(201);

  const dashboard = await request(app).get('/api/v1/finance/dashboard')
    .query({
      businessModel: 'contactUnlock', propertyId: rental.id,
      from: '2026-04-01', to: '2026-04-30'
    }).set(auth(rentalAgent));
  expect(dashboard.status).toBe(200);
  expect(dashboard.body.summary).toMatchObject({
    expectedRentTzs: 0, rentCollectedTzs: 20000,
    operatingProfitTzs: 0, cashFlowTzs: 20000
  });
  expect(dashboard.body.trends).toContainEqual(expect.objectContaining({
    month: '2026-04', expectedTzs: 0, collectedTzs: 20000, incomeTzs: 0
  }));
});

test('leaves optional staff empty and prevents unrelated-property leakage', async () => {
  const response = await request(app).get('/api/v1/finance/dashboard')
    .query({ businessModel: 'contactUnlock' }).set(auth(rentalAgent));
  expect(response.status).toBe(200);
  expect(response.body.properties.map((item) => item.id)).toContain(rental.id);
  expect(response.body.properties.map((item) => item.id)).not.toContain(otherRental.id);
  expect(response.body.properties.map((item) => item.id)).not.toContain(stay.id);
  expect(response.body.staff.some((item) => item.propertyId === otherRental.id)).toBe(false);
  expect((await request(app).get(p(otherRental, 'expenses')).set(auth(rentalAgent))).status).toBe(404);
});

test('uses succeeded booking payments once, excludes cancellations/refunds and exposes no assumed agent payout', async () => {
  const makeBooking = async (requestKey, status, paymentStatus) => {
    const booking = await Booking.create({
      propertyId: stay.id, requestKey, customerId: customer.id,
      checkIn: new Date('2026-03-10'), checkOut: new Date('2026-03-11'),
      guestName: 'Customer', subtotalTzs: 100000, feeTzs: 2000, totalTzs: 102000, status
    });
    const transaction = await PaymentTransaction.create({
      reference: `finance-${requestKey}`, purpose: 'accommodationBooking',
      amountTzs: 102000, currency: 'TZS', methodId: 'test',
      customerId: customer.id, listingId: stay.id, bookingId: booking.id,
      status: paymentStatus, verifiedAt: paymentStatus === 'succeeded' ? new Date('2026-03-10') : null
    });
    await booking.update({ paymentTransactionId: transaction.id });
  };
  await makeBooking('finance-paid', 'confirmed', 'succeeded');
  await makeBooking('finance-refund', 'confirmed', 'refunded');
  await makeBooking('finance-cancel', 'cancelled', 'succeeded');
  const dashboard = await request(app).get('/api/v1/finance/dashboard')
    .query({ businessModel: 'bookable' }).set(auth(stayAgent));
  expect(dashboard.status).toBe(200);
  expect(dashboard.body.summary.bookingRevenueTzs).toBe(100000);
  expect(dashboard.body.summary.platformPaymentsReceivedTzs).toBe(102000);
  expect(dashboard.body.summary).not.toHaveProperty('agentPayoutTzs');
  expect(dashboard.body.summary.incomeBasis).toMatch(/not agent payouts/);
});

test('creates idempotent due alerts and in-app notification for the owner', async () => {
  const bill = await request(app).post(p(rental, 'bills')).set(auth(rentalAgent)).send({
    category: 'water', provider: 'Water board', billingMonth: '2020-01',
    amountTzs: 10000, dueDate: '2020-01-01'
  });
  expect(bill.status).toBe(201);
  const notificationsBefore = await Notification.count({
    where: { userId: rentalAgent.id, title: 'Utility bill overdue' }
  });
  await refreshPropertyAlerts(rental, rentalAgent.id);
  await refreshPropertyAlerts(rental, rentalAgent.id);
  const alertCount = await FinancialAlert.count({
    where: { ownerId: rentalAgent.id, recordType: 'utilityBill', recordId: bill.body.record.id }
  });
  expect(alertCount).toBe(1);
  expect(await Notification.count({
    where: { userId: rentalAgent.id, title: 'Utility bill overdue' }
  })).toBe(notificationsBefore + 1);
  const otherAlerts = await request(app).get('/api/v1/finance/alerts').set(auth(otherAgent));
  expect(otherAlerts.body.alerts.some((alert) => alert.propertyId === rental.id)).toBe(false);
  expect((await request(app).get('/api/v1/finance/admin/overview').set(auth(admin))).status).toBe(200);
});
