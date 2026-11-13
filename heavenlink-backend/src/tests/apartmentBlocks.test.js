process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-apartment-block-secret-32-characters';
process.env.OTP_SECRET = 'test-only-apartment-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(), `haven-link-apartment-blocks-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const { generateToken } = require('../middleware/auth');
const { sequelize, syncDatabase, User, Property, AgentWorkspace } = require('../models');

const auth = (user) => ({ Authorization: 'Bearer ' + generateToken(user) });
let n = 0;
const makeAgent = async (workspace) => {
  n += 1;
  const user = await User.create({
    fullName: `Host ${n}`, email: `host-${n}@test.invalid`, phone: `+25573000${String(n).padStart(4, '0')}`,
    password: 'test-password-123', role: 'STAY_AGENT', verification: 'verified',
    capabilities: ['accommodationBooking']
  });
  await AgentWorkspace.create({ userId: user.id, workspace, status: 'active', source: 'registration' });
  return user;
};
const makeApartment = (agent) => Property.create({
  name: 'Block Test Apartment', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
  businessModel: 'bookable', category: 'shortStayApartment', agentId: agent.id,
  listingStatus: 'published', imageUrl: 'https://example.invalid/a.jpg', bedrooms: 3, bathrooms: 2,
  description: 'A furnished apartment for block tests.', managerName: 'Manager'
});

beforeAll(async () => { await syncDatabase(); }, 30000);
afterAll(async () => {
  await sequelize.close();
  fs.rmSync(process.env.SQLITE_STORAGE, { force: true });
});

describe('apartment capacity and booking rules', () => {
  it('stores rules for apartments and enforces them on availability checks', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const updated = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host)).send({
      maxGuests: 4,
      stayRules: { minNights: 2, maxNights: 10, checkInTime: '14:00', checkOutTime: '10:00', houseRules: 'No parties' }
    });
    expect(updated.status).toBe(200);
    const query = `/api/v1/bookings/availability/check?propertyId=${apartment.id}`;
    const tooMany = await request(app).get(`${query}&checkIn=2031-05-10&checkOut=2031-05-13&guestCount=5`);
    expect(tooMany.status).toBe(400);
    const tooShort = await request(app).get(`${query}&checkIn=2031-05-10&checkOut=2031-05-11&guestCount=2`);
    expect(tooShort.status).toBe(400);
    const tooLong = await request(app).get(`${query}&checkIn=2031-05-10&checkOut=2031-05-25&guestCount=2`);
    expect(tooLong.status).toBe(400);
    const ok = await request(app).get(`${query}&checkIn=2031-05-10&checkOut=2031-05-13&guestCount=4`);
    expect(ok.status).toBe(200);
    expect(ok.body.available).toBe(true);
  });

  it('stores location and photo labels, and rejects malformed ones', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const url = 'https://example.com/a.jpg';
    const ok = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host)).send({
      stayRules: { country: 'Tanzania', region: 'Dar es Salaam', photoLabels: { [url]: 'Bedroom' } }
    });
    expect(ok.status).toBe(200);
    expect(ok.body.property.stayRules.region).toBe('Dar es Salaam');
    expect(ok.body.property.stayRules.photoLabels[url]).toBe('Bedroom');
    const bad = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host)).send({
      stayRules: { photoLabels: { [url]: 'x'.repeat(41) } }
    });
    expect(bad.status).toBe(400);
    const longRegion = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host)).send({
      stayRules: { region: 'r'.repeat(81) }
    });
    expect(longRegion.status).toBe(400);
  });

  it('prices weekend nights and the cleaning fee, and ignores them for hotels', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const saved = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host)).send({
      stayRules: { weekendPriceTzs: 150000, cleaningFeeTzs: 20000, beds: 3 }
    });
    expect(saved.status).toBe(200);
    const query = `/api/v1/bookings/availability/check?propertyId=${apartment.id}`;
    // Fri, Sat and Sun nights: two weekend nights, one weekday-rate night.
    const quote = await request(app).get(`${query}&checkIn=2031-05-09&checkOut=2031-05-12&guestCount=2`);
    expect(quote.status).toBe(200);
    expect(quote.body.subtotal).toBe(150000 + 150000 + 100000 + 20000);
    const weekday = await request(app).get(`${query}&checkIn=2031-05-12&checkOut=2031-05-14&guestCount=2`);
    expect(weekday.body.subtotal).toBe(100000 * 2 + 20000);

    const invalid = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host))
      .send({ stayRules: { weekendPriceTzs: -5 } });
    expect(invalid.status).toBe(400);
  });

  it('rejects invalid rules and ignores them for hotels', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const bad = await request(app).put(`/api/v1/properties/${apartment.id}`).set(auth(host))
      .send({ stayRules: { minNights: 5, maxNights: 2 } });
    expect(bad.status).toBe(400);
    const hotel = await Property.create({
      name: 'Rules Hotel', city: 'Arusha', neighborhood: 'Njiro', priceTzs: 100000,
      businessModel: 'bookable', category: 'hotel', accommodationType: 'hotel', agentId: host.id,
      listingStatus: 'published', imageUrl: 'https://example.invalid/h.jpg', bedrooms: 1, bathrooms: 1,
      description: 'A hotel used for rules tests.', managerName: 'Manager'
    });
    const hotelUpdate = await request(app).put(`/api/v1/properties/${hotel.id}`).set(auth(host))
      .send({ maxGuests: 3, name: 'Rules Hotel Renamed' });
    expect(hotelUpdate.status).toBe(200);
    expect((await Property.findByPk(hotel.id)).maxGuests).toBeNull();
  });
});

describe('listing photo uploads', () => {
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)
  ]);

  it('stores agent photos and serves them publicly', async () => {
    const host = await makeAgent('APARTMENT');
    const upload = await request(app).post('/api/v1/properties/photos').set(auth(host))
      .attach('photos', png, 'living-room.png');
    expect(upload.status).toBe(201);
    expect(upload.body.urls).toHaveLength(1);
    const path = new URL(upload.body.urls[0]).pathname;
    const fetched = await request(app).get(path);
    expect(fetched.status).toBe(200);
    expect(fetched.headers['content-type']).toMatch(/image\/png/);
  });

  it('rejects non-images, anonymous uploads and invalid names', async () => {
    const host = await makeAgent('APARTMENT');
    const bad = await request(app).post('/api/v1/properties/photos').set(auth(host))
      .attach('photos', Buffer.from('<script>alert(1)</script>'.repeat(3)), 'x.png');
    expect(bad.status).toBe(400);
    const anonymous = await request(app).post('/api/v1/properties/photos')
      .attach('photos', png, 'a.png');
    expect(anonymous.status).toBe(401);
    const traversal = await request(app).get('/api/v1/properties/photos/..%2F..%2Fsecret.png');
    expect(traversal.status).toBe(404);
  });
});

describe('apartment date blocks', () => {
  it('blocks dates, hides them from availability and unblocks them', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const url = `/api/v1/agents/apartments/${apartment.id}/blocks`;
    const created = await request(app).post(url).set(auth(host))
      .send({ startDate: '2031-03-10', endDate: '2031-03-15', reason: 'Owner stay' });
    expect(created.status).toBe(201);

    const query = '/api/v1/bookings/availability/check?propertyId=' + apartment.id;
    const blocked = await request(app).get(`${query}&checkIn=2031-03-12&checkOut=2031-03-14`);
    expect(blocked.body.available).toBe(false);
    const open = await request(app).get(`${query}&checkIn=2031-03-15&checkOut=2031-03-17`);
    expect(open.body.available).toBe(true);

    const listed = await request(app).get(url).set(auth(host));
    expect(listed.body.blocks).toHaveLength(1);
    const removed = await request(app).delete(`${url}/${created.body.block.id}`).set(auth(host));
    expect(removed.status).toBe(200);
    const reopened = await request(app).get(`${query}&checkIn=2031-03-12&checkOut=2031-03-14`);
    expect(reopened.body.available).toBe(true);
  });

  it('rejects invalid ranges and agents without the apartment workspace', async () => {
    const host = await makeAgent('APARTMENT');
    const apartment = await makeApartment(host);
    const url = `/api/v1/agents/apartments/${apartment.id}/blocks`;
    const invalid = await request(app).post(url).set(auth(host))
      .send({ startDate: '2031-03-15', endDate: '2031-03-10', reason: 'Bad' });
    expect(invalid.status).toBe(400);

    const hotelOnly = await makeAgent('HOTEL');
    const foreign = await request(app).post(url).set(auth(hotelOnly))
      .send({ startDate: '2031-04-01', endDate: '2031-04-03', reason: 'Nope' });
    expect(foreign.status).toBe(403);
    const other = await makeAgent('APARTMENT');
    const notOwner = await request(app).get(url).set(auth(other));
    expect(notOwner.status).toBe(403);
  });
});
