process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-haven-link-jwt-secret-32-characters';
process.env.OTP_SECRET = 'test-only-haven-link-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(),
  `haven-link-reviews-test-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const {
  sequelize, syncDatabase, User, Property, Booking, PaymentTransaction, Review, Notification, ProblemReport, AdminAuditEvent
} = require('../models');
const { generateToken } = require('../middleware/auth');

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(40)
]);
const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.alloc(40)]);

let customer;
let other;
let agent;
let otherAgent;
let admin;
let stay;
let emptyStay;
let rental;
const bookings = {};
const auth = (user) => ({ Authorization: `Bearer ${generateToken(user)}` });
const nine = (overrides = {}) => ({
  overallRating: 5,
  cleanliness: 4,
  accuracy: 4,
  checkIn: 3,
  communication: 5,
  location: 5,
  value: 3,
  comfort: 4,
  amenities: 2,
  ...overrides
});

const makeUser = (name, role, n) => User.create({
  fullName: name,
  email: `${role.toLowerCase()}-${n}@reviews.invalid`,
  phone: `+2557000002${String(n).padStart(2, '0')}`,
  password: 'test-password-123',
  role,
  verification: 'verified'
});

const makeBooking = (key, owner, fields) => Booking.create({
  propertyId: stay.id,
  requestKey: key,
  customerId: owner.id,
  checkIn: new Date('2026-01-10T12:00:00.000Z'),
  checkOut: new Date('2026-01-12T10:00:00.000Z'),
  guestName: owner.fullName,
  subtotalTzs: 300000,
  feeTzs: 6000,
  totalTzs: 306000,
  ...fields
});

const addPayment = async (booking, fields = {}) => {
  const payment = await PaymentTransaction.create({
    reference: `review-payment-${booking.requestKey}`,
    purpose: 'accommodationBooking',
    amountTzs: booking.totalTzs,
    methodId: 'test',
    customerId: booking.customerId,
    bookingId: booking.id,
    status: 'succeeded',
    verifiedAt: new Date(),
    ...fields
  });
  await booking.update({ paymentTransactionId: payment.id });
  return payment;
};

const property = (name, agentId, businessModel) => Property.create({
  name,
  city: 'Dar es Salaam',
  neighborhood: 'Masaki',
  priceTzs: 150000,
  businessModel,
  category: businessModel === 'bookable' ? 'hotel' : 'house',
  imageUrl: 'https://example.invalid/stay.jpg',
  bedrooms: 1,
  bathrooms: 1,
  description: 'A verified accommodation for review tests.',
  managerName: 'Manager',
  listingStatus: 'published',
  agentId
});

beforeAll(async () => {
  await syncDatabase();
  customer = await makeUser('Amina Juma Mwangi', 'CUSTOMER', 1);
  other = await makeUser('Other Guest', 'CUSTOMER', 2);
  agent = await makeUser('Stay Agent', 'STAY_AGENT', 3);
  otherAgent = await makeUser('Other Agent', 'STAY_AGENT', 4);
  admin = await makeUser('Admin', 'ADMIN', 5);
  stay = await property('Reviewed stay', agent.id, 'bookable');
  emptyStay = await property('Brand new stay', agent.id, 'bookable');
  rental = await property('A rental', agent.id, 'contactUnlock');
  const now = Date.now();
  const day = 86400000;
  bookings.completed = await makeBooking('completed-1', customer, {
    status: 'completed', checkedOutAt: new Date(now - 2 * day)
  });
  bookings.unverified = await makeBooking('unverified-1', customer, { status: 'completed' });
  bookings.upcoming = await makeBooking('upcoming-1', customer, {
    status: 'confirmed',
    checkIn: new Date(now + 5 * day),
    checkOut: new Date(now + 7 * day)
  });
  bookings.ongoing = await makeBooking('ongoing-1', customer, {
    status: 'confirmed',
    checkIn: new Date(now - day),
    checkOut: new Date(now + day)
  });
  bookings.cancelled = await makeBooking('cancelled-1', customer, { status: 'cancelled' });
  bookings.expired = await makeBooking('expired-1', customer, {
    status: 'completed', checkedOutAt: new Date(now - 20 * day)
  });
  bookings.otherGuest = await makeBooking('other-1', other, {
    status: 'completed', checkedOutAt: new Date(now - day)
  });
  await addPayment(bookings.completed);
  await addPayment(bookings.expired);
  await addPayment(bookings.otherGuest);
}, 30000);

afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

test('customer trips are split into upcoming, ongoing and completed phases', async () => {
  const trips = await request(app).get('/api/v1/reviews/trips').set(auth(customer));
  expect(trips.status).toBe(200);
  const phase = (id) => trips.body.trips.find((trip) => trip.id === id);
  expect(phase(bookings.upcoming.id)).toMatchObject({ phase: 'upcoming', canReview: false });
  expect(phase(bookings.ongoing.id)).toMatchObject({ phase: 'ongoing', canReview: false });
  expect(phase(bookings.completed.id)).toMatchObject({ phase: 'completed', canReview: true });
  expect(phase(bookings.completed.id).paymentStatus).toBe('verified');
  expect(phase(bookings.unverified.id).canReview).toBe(false);
  expect(phase(bookings.expired.id).canReview).toBe(false);
  expect(phase(bookings.cancelled.id)).toBeUndefined();
  expect(phase(bookings.otherGuest.id)).toBeUndefined();
});

test('review eligibility requires a matching, verified, unrefunded booking payment', async () => {
  const booking = await makeBooking('payment-cases', customer, {
    status: 'completed', checkedOutAt: new Date()
  });
  const eligibility = () => request(app).get(`/api/v1/reviews/eligibility/${booking.id}`).set(auth(customer));
  const submit = () => request(app).post('/api/v1/reviews').set(auth(customer))
    .send({ bookingId: booking.id, ...nine() });
  expect((await eligibility()).body.eligible).toBe(false);
  expect((await submit()).status).toBe(403);

  const payment = await addPayment(booking);
  const cases = [
    { status: 'pending', verifiedAt: null },
    { status: 'failed', verifiedAt: null },
    { status: 'refunded' },
    { verifiedAt: null },
    { purpose: 'rentalContactUnlock' },
    { customerId: other.id },
    { bookingId: bookings.otherGuest.id },
    { amountTzs: booking.totalTzs - 1 }
  ];
  const baseline = {
    status: 'succeeded', verifiedAt: new Date(), purpose: 'accommodationBooking',
    customerId: customer.id, bookingId: booking.id, amountTzs: booking.totalTzs
  };
  for (const change of cases) {
    await payment.update({ ...baseline, ...change });
    expect((await submit()).status).toBe(403);
  }
  const trips = await request(app).get('/api/v1/reviews/trips').set(auth(customer));
  const trip = trips.body.trips.find((item) => item.id === booking.id);
  expect(trip.canReview).toBe(false);
  expect(trip.paymentStatus).toBe('unverified');
  await payment.update({ ...baseline, status: 'pending', verifiedAt: null });
  const pendingTrips = await request(app).get('/api/v1/reviews/trips').set(auth(customer));
  expect(pendingTrips.body.trips.find((item) => item.id === booking.id).paymentStatus).toBe('pending');
  await payment.update({ ...baseline, status: 'refunded' });
  const refundedTrips = await request(app).get('/api/v1/reviews/trips').set(auth(customer));
  expect(refundedTrips.body.trips.find((item) => item.id === booking.id).paymentStatus).toBe('refunded');
  await payment.update(baseline);
  expect((await eligibility()).body.eligible).toBe(true);
  await booking.update({ checkedOutAt: new Date(Date.now() + 86400000) });
  expect((await eligibility()).body.eligible).toBe(false);
  expect((await submit()).status).toBe(403);
});

test.each([
  ['upcoming', 'upcoming'],
  ['ongoing', 'ongoing'],
  ['unverified checkout', 'unverified'],
  ['cancelled', 'cancelled'],
  ['outside the 14 day window', 'expired'],
  ['someone else\'s', 'otherGuest']
])('a %s stay cannot be reviewed', async (_label, key) => {
  const response = await request(app).post('/api/v1/reviews').set(auth(customer))
    .send({ bookingId: bookings[key].id, ...nine() });
  expect(response.status).toBe(403);
  expect(await Review.count()).toBe(0);
});

test('rentals cannot be reviewed even with a completed booking', async () => {
  const rentalBooking = await Booking.create({
    propertyId: rental.id, requestKey: 'rental-1', customerId: customer.id,
    checkIn: new Date('2026-01-01'), checkOut: new Date('2026-01-03'), guestName: 'Test Guest',
    subtotalTzs: 1, feeTzs: 0, totalTzs: 1, status: 'completed', checkedOutAt: new Date()
  });
  const response = await request(app).post('/api/v1/reviews').set(auth(customer))
    .send({ bookingId: rentalBooking.id, ...nine() });
  expect(response.status).toBe(403);
});

test('invalid or incomplete ratings are rejected', async () => {
  for (const bad of [{ cleanliness: 6 }, { comfort: 0 }, { amenities: undefined }, { overallRating: 'x' }]) {
    const response = await request(app).post('/api/v1/reviews').set(auth(customer))
      .send({ bookingId: bookings.completed.id, ...nine(bad) });
    expect(response.status).toBe(400);
  }
  const short = await request(app).post('/api/v1/reviews').set(auth(customer))
    .send({ bookingId: bookings.completed.id, ...nine(), comment: 'ok' });
  expect(short.status).toBe(400);
});

test('an agent cannot create a review through agent permissions', async () => {
  const response = await request(app).post('/api/v1/reviews').set(auth(agent))
    .send({ bookingId: bookings.completed.id, ...nine() });
  expect(response.status).toBe(403);
});

test('a verified guest submits nine independent ratings with a sanitized comment and photo', async () => {
  const submitted = await request(app).post('/api/v1/reviews').set(auth(customer))
    .field('bookingId', bookings.completed.id)
    .field('overallRating', '5')
    .field('cleanliness', '4').field('accuracy', '4').field('checkIn', '3')
    .field('communication', '5').field('location', '5').field('value', '3')
    .field('comfort', '4').field('amenities', '2')
    .field('comment', 'Lovely view <script>alert(1)</script> and a friendly host.')
    .attach('photos', png, 'room.png');
  expect(submitted.status).toBe(201);
  expect(submitted.body.review).toMatchObject({
    overallRating: 5, comfort: 4, amenities: 2, propertyId: stay.id, bookingId: bookings.completed.id
  });
  expect(submitted.body.review.comment).not.toContain('<script>');
  expect(submitted.body.review.images).toHaveLength(1);

  const duplicate = await request(app).post('/api/v1/reviews').set(auth(customer))
    .send({ bookingId: bookings.completed.id, ...nine() });
  expect(duplicate.status).toBe(409);

  const notes = await Notification.findAll({ where: { userId: [customer.id, agent.id] } });
  expect(notes.map((note) => note.message)).toEqual(expect.arrayContaining([
    'Thank you for sharing your experience.',
    'A guest has reviewed one of your properties.'
  ]));
});

test('public reviews use the independent overall rating, expose photos and hide private data', async () => {
  const page = await request(app).get(`/api/v1/reviews/properties/${stay.id}`);
  expect(page.status).toBe(200);
  expect(page.body.summary).toMatchObject({
    count: 1,
    overall: 5,
    criteria: {
      cleanliness: 4, accuracy: 4, checkIn: 3, communication: 5,
      location: 5, value: 3, comfort: 4, amenities: 2
    }
  });
  const review = page.body.reviews[0];
  expect(review.reviewer.displayName).toBe('Amina M.');
  expect(review.bookingId).toBeUndefined();
  expect(review.reviewerId).toBeUndefined();
  expect(review.stayDate).toBeTruthy();
  const photo = await request(app).get(review.images[0]);
  expect(photo.status).toBe(200);
  expect(photo.headers['content-type']).toMatch(/png/);
  expect(JSON.stringify(page.body)).not.toMatch(/problem|evidence/i);

  const home = await request(app).get(`/api/v1/properties/${stay.id}`);
  expect(home.body.property).toMatchObject({ rating: 5, reviewCount: 1 });
  const empty = await request(app).get(`/api/v1/reviews/properties/${emptyStay.id}`);
  expect(empty.body.summary).toMatchObject({ count: 0, overall: 0 });
  expect((await request(app).get(`/api/v1/reviews/properties/${rental.id}`)).status).toBe(404);
});

test('uploads are validated by content, type and size', async () => {
  const guest = await makeUser('Photo Guest', 'CUSTOMER', 6);
  const booking = await makeBooking('photo-1', guest, { status: 'completed', checkedOutAt: new Date() });
  await addPayment(booking);
  const attach = (buffer, name) => request(app).post('/api/v1/reviews').set(auth(guest))
    .field('bookingId', booking.id).field('overallRating', '4').field('cleanliness', '4')
    .field('accuracy', '4').field('checkIn', '4').field('communication', '4')
    .field('location', '4').field('value', '4').field('comfort', '4').field('amenities', '4')
    .attach('photos', buffer, name);
  expect((await attach(Buffer.from('<script>alert(1)</script>'.padEnd(40)), 'x.png')).status).toBe(400);
  expect((await attach(pdf, 'x.pdf')).status).toBe(400);
  expect((await attach(Buffer.concat([png, Buffer.alloc(5 * 1024 * 1024)]), 'big.png')).status).toBe(400);
  expect(await Review.count({ where: { bookingId: booking.id } })).toBe(0);
});

test('review filters and sorting use stored data', async () => {
  const guest = await User.findOne({ where: { email: 'customer-6@reviews.invalid' } });
  const booking = await Booking.findOne({ where: { requestKey: 'photo-1' } });
  const low = await request(app).post('/api/v1/reviews').set(auth(guest))
    .send({ bookingId: booking.id, ...nine({ overallRating: 2, cleanliness: 1, comment: 'Needs work overall.' }) });
  expect(low.status).toBe(201);

  const summary = await request(app).get(`/api/v1/reviews/properties/${stay.id}`);
  expect(summary.body.summary.overall).toBe(3.5);
  const lowest = await request(app).get(`/api/v1/reviews/properties/${stay.id}?sort=lowest`);
  expect(lowest.body.reviews[0].overallRating).toBe(2);
  const fives = await request(app).get(`/api/v1/reviews/properties/${stay.id}?rating=5`);
  expect(fives.body.reviews).toHaveLength(1);
  const clean = await request(app).get(`/api/v1/reviews/properties/${stay.id}?category=cleanliness&minRating=4`);
  expect(clean.body.reviews).toHaveLength(1);
  const photos = await request(app).get(`/api/v1/reviews/properties/${stay.id}?withPhotos=true`);
  expect(photos.body.reviews).toHaveLength(1);
});

test('agents respond only to their own reviews and cannot alter guest content', async () => {
  const review = await Review.findOne({ where: { bookingId: bookings.completed.id } });
  const denied = await request(app).post(`/api/v1/reviews/${review.id}/response`)
    .set(auth(otherAgent)).send({ response: 'Not my property.' });
  expect(denied.status).toBe(404);
  const customerDenied = await request(app).post(`/api/v1/reviews/${review.id}/response`)
    .set(auth(customer)).send({ response: 'Self reply.' });
  expect(customerDenied.status).toBe(403);
  const ok = await request(app).post(`/api/v1/reviews/${review.id}/response`)
    .set(auth(agent)).send({ response: 'Thank you for staying with us!' });
  expect(ok.status).toBe(200);

  const mine = await request(app).get('/api/v1/reviews/agent').set(auth(agent));
  expect(mine.body.reviews).toHaveLength(2);
  expect(mine.body.properties.find((item) => item.id === stay.id).summary.count).toBe(2);
  expect((await request(app).get('/api/v1/reviews/agent').set(auth(otherAgent))).body.reviews).toHaveLength(0);

  const publicPage = await request(app).get(`/api/v1/reviews/properties/${stay.id}`);
  expect(publicPage.body.reviews.find((item) => item.id === review.id).agentResponse)
    .toBe('Thank you for staying with us!');
  const reportReview = await request(app).post(`/api/v1/reviews/${review.id}/reports`)
    .set(auth(otherAgent)).send({ reason: 'Violates policy.' });
  expect(reportReview.status).toBe(403);
});

test('moderation hides photos and recalculates ratings', async () => {
  const review = await Review.findOne({ where: { bookingId: bookings.completed.id } });
  const url = `/api/v1/reviews/photos/${review.images[0]}`;
  expect((await request(app).get(url)).status).toBe(200);
  const hide = await request(app).patch(`/api/v1/admin/reviews/${review.id}/moderation`)
    .set(auth(admin)).send({ status: 'hidden', reason: 'Policy violation confirmed.' });
  expect(hide.status).toBe(200);
  expect((await request(app).get(url)).status).toBe(404);
  const home = await request(app).get(`/api/v1/properties/${stay.id}`);
  expect(home.body.property).toMatchObject({ rating: 2, reviewCount: 1 });
  await request(app).patch(`/api/v1/admin/reviews/${review.id}/moderation`)
    .set(auth(admin)).send({ status: 'published', reason: 'Within policy after review.' });

  const filtered = await request(app).get(`/api/v1/admin/reviews?propertyId=${stay.id}&agentId=${agent.id}`)
    .set(auth(admin));
  expect(filtered.body.reviews).toHaveLength(2);
  const none = await request(app).get(`/api/v1/admin/reviews?agentId=${otherAgent.id}`).set(auth(admin));
  expect(none.body.reviews).toHaveLength(0);
});

describe('private problem reports', () => {
  let ordinary;
  let sensitive;

  test('a report can be submitted without a review during an ongoing stay', async () => {
    const response = await request(app).post('/api/v1/reports').set(auth(customer))
      .field('bookingId', bookings.ongoing.id)
      .field('category', 'utilities')
      .field('severity', 'urgent')
      .field('description', 'There has been no water in the room since last night.')
      .attach('evidence', pdf, 'proof.pdf');
    expect(response.status).toBe(201);
    ordinary = response.body.report;
    expect(ordinary.reference).toMatch(/^HLR-[0-9A-F]{8}$/);
    expect(ordinary.severity).toBe('urgent');
    expect(await Review.count({ where: { bookingId: bookings.ongoing.id } })).toBe(0);

    const adminNote = await Notification.findOne({ where: { userId: admin.id } });
    expect(adminNote.title).toMatch(/^Priority/);
    expect(adminNote.message).toBe('New customer problem report received.');
    expect(adminNote.message).not.toMatch(/water/);
    const agentNote = await Notification.findOne({ where: { userId: agent.id, title: 'Customer concern reported' } });
    expect(agentNote.message).toBe('A customer has reported a concern about your property.');
  });

  test('an upcoming, cancelled or foreign booking cannot be reported', async () => {
    for (const [user, key] of [[customer, 'upcoming'], [customer, 'cancelled'], [other, 'ongoing']]) {
      const response = await request(app).post('/api/v1/reports').set(auth(user))
        .send({ bookingId: bookings[key].id, category: 'other', description: 'Some real concern here.' });
      expect(response.status).toBe(403);
    }
  });

  test('ordinary reports reach the assigned agent only', async () => {
    const agentList = await request(app).get('/api/v1/reports/agent').set(auth(agent));
    expect(agentList.body.reports.map((report) => report.id)).toContain(ordinary.id);
    expect((await request(app).get('/api/v1/reports/agent').set(auth(otherAgent))).body.reports).toHaveLength(0);
    expect((await request(app).get('/api/v1/reports/agent').set(auth(customer))).status).toBe(403);
    const evidenceUrl = ordinary.evidence[0];
    expect((await request(app).get(evidenceUrl).set(auth(agent))).status).toBe(200);
    expect((await request(app).get(evidenceUrl).set(auth(otherAgent))).status).toBe(404);
    expect((await request(app).get(evidenceUrl)).status).toBe(401);
    expect((await request(app).get(evidenceUrl).set(auth(other))).status).toBe(404);
  });

  test('sensitive complaints go to Admin first and stay hidden from the agent', async () => {
    const response = await request(app).post('/api/v1/reports').set(auth(customer))
      .send({ bookingId: bookings.completed.id, category: 'staff_behavior', description: 'The agent harassed me during the stay.' });
    expect(response.status).toBe(201);
    sensitive = response.body.report;
    const stored = await ProblemReport.findByPk(sensitive.id);
    expect(stored).toMatchObject({ visibilityClassification: 'sensitive', sharedWithAgent: false });
    const agentList = await request(app).get('/api/v1/reports/agent').set(auth(agent));
    expect(agentList.body.reports.map((report) => report.id)).not.toContain(sensitive.id);
    const agentNotes = await Notification.findAll({ where: { userId: agent.id } });
    expect(agentNotes.filter((note) => note.title === 'Customer concern reported')).toHaveLength(1);

    const adminList = await request(app).get('/api/v1/reports/admin?classification=sensitive').set(auth(admin));
    expect(adminList.body.reports.map((report) => report.id)).toEqual([sensitive.id]);
    expect(adminList.body.stats.sensitive).toBe(1);
    expect((await request(app).get('/api/v1/reports/admin').set(auth(agent))).status).toBe(403);

    const agentReply = await request(app).post(`/api/v1/reports/agent/${sensitive.id}/reply`)
      .set(auth(agent)).send({ body: 'Trying to reply.' });
    expect(agentReply.status).toBe(404);
  });

  test('admin controls notes, disclosure, status and audit trail', async () => {
    const internal = await request(app).post(`/api/v1/reports/admin/${sensitive.id}/notes`)
      .set(auth(admin)).send({ body: 'Internal investigation note.', visibility: 'internal' });
    expect(internal.status).toBe(201);
    const blocked = await request(app).post(`/api/v1/reports/admin/${sensitive.id}/notes`)
      .set(auth(admin)).send({ body: 'For the agent.', visibility: 'agent' });
    expect(blocked.status).toBe(409);
    await request(app).post(`/api/v1/reports/admin/${sensitive.id}/notes`)
      .set(auth(admin)).send({ body: 'We are looking into this and will update you.', visibility: 'customer' });

    const patch = await request(app).patch(`/api/v1/reports/admin/${sensitive.id}`)
      .set(auth(admin)).send({ status: 'awaiting_customer', assignedStaffId: admin.id });
    expect(patch.status).toBe(200);
    const badAssign = await request(app).patch(`/api/v1/reports/admin/${sensitive.id}`)
      .set(auth(admin)).send({ assignedStaffId: customer.id });
    expect(badAssign.status).toBe(400);

    const mine = await request(app).get('/api/v1/reports/mine').set(auth(customer));
    const own = mine.body.reports.find((report) => report.id === sensitive.id);
    expect(own.status).toBe('awaiting_customer');
    expect(own.notes.map((note) => note.body)).toEqual(['We are looking into this and will update you.']);
    expect(JSON.stringify(own)).not.toMatch(/Internal investigation|assignedStaffId|sharedWithAgent/);
    expect((await request(app).get('/api/v1/reports/mine').set(auth(other))).body.reports).toHaveLength(0);

    const reply = await request(app).post(`/api/v1/reports/${sensitive.id}/reply`)
      .set(auth(customer)).send({ body: 'Thank you, here is more detail.' });
    expect(reply.status).toBe(201);
    expect((await ProblemReport.findByPk(sensitive.id)).status).toBe('under_review');

    await request(app).patch(`/api/v1/reports/admin/${sensitive.id}`)
      .set(auth(admin)).send({ status: 'resolved' });
    expect((await ProblemReport.findByPk(sensitive.id)).resolvedAt).not.toBeNull();
    const updates = await Notification.findAll({ where: { userId: customer.id, message: 'Your HavenLink report has been updated.' } });
    expect(updates.length).toBeGreaterThanOrEqual(2);
    const events = await AdminAuditEvent.findAll({ where: { entityType: 'ProblemReport' } });
    expect(events.length).toBeGreaterThanOrEqual(4);
  });

  test('agents reply and propose resolutions on shared reports; admin can filter', async () => {
    await request(app).patch(`/api/v1/reports/admin/${ordinary.id}`)
      .set(auth(admin)).send({ status: 'awaiting_agent' });
    const reply = await request(app).post(`/api/v1/reports/agent/${ordinary.id}/reply`)
      .set(auth(agent)).send({ body: 'We have sent a technician.', kind: 'resolution' });
    expect(reply.status).toBe(201);
    expect((await ProblemReport.findByPk(ordinary.id)).status).toBe('under_review');
    const urgent = await request(app).get('/api/v1/reports/admin?severity=urgent&category=utilities')
      .set(auth(admin));
    expect(urgent.body.reports.map((report) => report.id)).toEqual([ordinary.id]);
    expect(urgent.body.reports[0].notes[0].kind).toBe('resolution');
  });

  test('private reports never appear in public review data', async () => {
    const page = await request(app).get(`/api/v1/reviews/properties/${stay.id}`);
    const serialized = JSON.stringify(page.body);
    expect(serialized).not.toContain(ordinary.reference);
    expect(serialized).not.toContain('no water');
  });
});
