process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-only-haven-link-jwt-secret-32-characters';
process.env.OTP_SECRET = 'test-only-haven-link-otp-secret-32-characters';
process.env.SQLITE_STORAGE = require('path').join(
  require('os').tmpdir(),
  `haven-link-room-inventory-${process.pid}.sqlite`
);

const fs = require('fs');
const request = require('supertest');
const { app } = require('../server');
const {
  sequelize,
  syncDatabase,
  User,
  Property,
  RoomType,
  Room,
  RoomAvailabilityBlock,
  Booking,
  PaymentTransaction,
  WalkInReservation,
  WalkInRoomSegment,
  AdminAuditEvent
} = require('../models');
const { generateToken } = require('../middleware/auth');
const paymentService = require('../services/paymentService');
const { unavailableRoomIds } = require('../services/roomAvailability');

jest.setTimeout(30000);

const authorization = (user) => ({
  Authorization: `Bearer ${generateToken(user)}`
});

const futureDates = () => {
  const start = new Date();
  start.setUTCDate(start.getUTCDate() + 10);
  start.setUTCHours(12, 0, 0, 0);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 2);
  return { checkIn: start.toISOString(), checkOut: end.toISOString() };
};

let agent;
let firstCustomer;
let secondCustomer;
let admin;
let hotel;
let motel;
let roomType;

const createRoomType = (listingId, totalRooms = 1) =>
  RoomType.create({
    listingId,
    name: 'Deluxe',
    description: 'Comfortable room with a private bathroom.',
    nightlyPriceTzs: 120000,
    capacity: 2,
    totalRooms
  });

const createProperty = (name, accommodationType = 'hotel') =>
  Property.create({
    name,
    city: 'Arusha',
    neighborhood: 'Central',
    priceTzs: 120000,
    businessModel: 'bookable',
    category: accommodationType === 'lodge' ? 'lodge' : 'hotel',
    accommodationType,
    imageUrl: 'https://example.invalid/stay.jpg',
    bedrooms: 1,
    bathrooms: 1,
    description: 'A multi-room accommodation for room inventory tests.',
    managerName: 'Stay Agent',
    listingStatus: 'published',
    latitude: -3.0,
    longitude: 36.0,
    agentId: agent.id
  });

const createBooking = (customer, property, type, requestKey, dates, guestCount = 2) =>
  request(app)
    .post('/api/v1/bookings')
    .set(authorization(customer))
    .send({
      propertyId: property.id,
      roomTypeId: type.id,
      requestKey,
      checkIn: dates.checkIn,
      checkOut: dates.checkOut,
      guestName: customer.fullName,
      guestCount
    });

beforeAll(async () => {
  await syncDatabase();
  agent = await User.create({
    fullName: 'Inventory Agent',
    email: 'inventory-agent@haven.invalid',
    phone: '+255700000901',
    password: 'test-password-123',
    role: 'STAY_AGENT',
    verification: 'verified'
  });
  admin = await User.create({
    fullName: 'Inventory Admin',
    email: 'inventory-admin@haven.invalid',
    phone: '+255700000904',
    password: 'test-password-123',
    role: 'ADMIN',
    verification: 'verified'
  });
  firstCustomer = await User.create({
    fullName: 'First Guest',
    email: 'inventory-guest-one@haven.invalid',
    phone: '+255700000902',
    password: 'test-password-123',
    role: 'CUSTOMER',
    verification: 'verified'
  });
  secondCustomer = await User.create({
    fullName: 'Second Guest',
    email: 'inventory-guest-two@haven.invalid',
    phone: '+255700000903',
    password: 'test-password-123',
    role: 'CUSTOMER',
    verification: 'verified'
  });
  hotel = await createProperty('Hundred Room Hotel');
  motel = await createProperty('Roadside Motel', 'motel');
});

afterAll(async () => {
  await sequelize.close();
  for (const suffix of ['', '-shm', '-wal']) {
    const file = `${process.env.SQLITE_STORAGE}${suffix}`;
    if (fs.existsSync(file)) fs.unlinkSync(file);
  }
});

describe('physical room inventory', () => {
  test('agents add floorless rooms with flexible identifiers and rename generated rooms safely', async () => {
    const lodge = await createProperty('Small Lodge', 'lodge');
    const add = (user, roomNumbers) => request(app)
      .post(`/api/v1/agents/rooms/${lodge.id}/manual`)
      .set(authorization(user)).send({ roomNumbers });
    expect((await add(firstCustomer, ['101'])).status).toBe(403);
    const created = await add(agent, ['101', 'A01', 'VIP-B', 'G-2', 'C']);
    expect(created.status).toBe(201);
    expect(created.body.rooms).toHaveLength(5);
    expect(created.body.rooms.every((room) => room.floorId === null)).toBe(true);
    expect((await add(agent, ['a01'])).status).toBe(409);
    expect((await add(agent, ['', 'bad/name'])).status).toBe(400);
    const room = created.body.rooms[0];
    const rename = (name) => request(app).patch(`/api/v1/agents/rooms/${lodge.id}/${room.id}`)
      .set(authorization(agent)).send({ roomNumber: name });
    expect((await rename('vip-b')).status).toBe(409);
    expect((await rename('X-101')).status).toBe(200);
    expect((await Room.findByPk(room.id)).roomNumber).toBe('X-101');
    expect(await AdminAuditEvent.count({ where: { entityType: 'Room', entityId: room.id, action: 'ROOM_IDENTIFIER_CHANGED' } })).toBe(1);
  });

  test('inventory model changes require confirmation and cannot erase history or room inventory', async () => {
    const apartment = await Property.create({
      name: 'Apartment Migration', city: 'Arusha', neighborhood: 'Central', priceTzs: 100000,
      businessModel: 'bookable', category: 'shortStayApartment',
      imageUrl: 'https://example.invalid/apartment.jpg', bedrooms: 1, bathrooms: 1,
      description: 'An apartment for inventory model migration tests.',
      managerName: 'Stay Agent', listingStatus: 'draft', agentId: agent.id
    });
    const edit = (body) => request(app).put(`/api/v1/properties/${apartment.id}`)
      .set(authorization(agent)).send(body);
    expect((await edit({ category: 'hotel', accommodationType: 'hotel' })).status).toBe(409);
    const accepted = await edit({ category: 'hotel', accommodationType: 'hotel', confirmInventoryModelChange: true });
    expect(accepted.status).toBe(200);
    expect(await AdminAuditEvent.count({ where: {
      entityType: 'Property', entityId: apartment.id, action: 'PROPERTY_INVENTORY_MODEL_CHANGED'
    } })).toBe(1);
    await Room.create({ propertyId: apartment.id, roomNumber: 'A01' });
    const blocked = await edit({ category: 'shortStayApartment', confirmInventoryModelChange: true });
    expect(blocked.status).toBe(409);
    expect((await apartment.reload()).category).toBe('hotel');
    expect((await edit({ category: 'shortStayApartment', accommodationType: 'hotel' })).status).toBe(400);
  });

  test('inventory creation rejects a property model changed after its initial lookup', async () => {
    for (const kind of ['manual', 'generate', 'category']) {
      const property = await createProperty(`Changed ${kind}`);
      const stale = await Property.findByPk(property.id);
      await property.update({ category: 'shortStayApartment', accommodationType: null });
      const lookup = jest.spyOn(Property, 'findByPk').mockResolvedValueOnce(stale);
      try {
        let response;
        if (kind === 'manual') {
          response = await request(app).post(`/api/v1/agents/rooms/${property.id}/manual`)
            .set(authorization(agent)).send({ roomNumbers: ['A01'] });
        } else if (kind === 'generate') {
          response = await request(app).post(`/api/v1/agents/rooms/${property.id}/generate`)
            .set(authorization(agent)).send({ floors: [{ label: 'Ground', roomCount: 1 }] });
        } else {
          response = await request(app).post('/api/v1/agents/room-types')
            .set(authorization(agent)).send({
              listingId: property.id, name: 'Standard', nightlyPriceTzs: 10000,
              capacity: 2, totalRooms: 1
            });
        }
        expect(response.status).toBe(409);
        expect(await Room.count({ where: { propertyId: property.id } })).toBe(0);
        expect(await RoomType.count({ where: { listingId: property.id } })).toBe(0);
      } finally {
        lookup.mockRestore();
      }
    }
  });

  test('property and room amenities preserve optional descriptions through agent APIs', async () => {
    const property = await createProperty('Amenity Details Hotel');
    const amenities = [
      { name: 'Breakfast', description: 'Served daily from 6:30 to 10:00.' },
      { name: 'Parking' }
    ];
    const propertyUpdate = await request(app).put(`/api/v1/properties/${property.id}`)
      .set(authorization(agent)).send({
        amenities: ['Breakfast', 'Parking'],
        amenityDetails: amenities
      });
    expect(propertyUpdate.status).toBe(200);
    expect(propertyUpdate.body.property.amenityDetails).toEqual(amenities);
    expect((await request(app).put(`/api/v1/properties/${property.id}`)
      .set(authorization(agent)).send({
        amenityDetails: [{ name: '', description: 'invalid' }]
      })).status).toBe(400);

    const roomTypeResponse = await request(app).post('/api/v1/agents/room-types')
      .set(authorization(agent)).send({
        listingId: property.id, name: 'Deluxe', nightlyPriceTzs: 100000,
        capacity: 2, totalRooms: 1, amenities: ['Wi-Fi'],
        amenityDetails: [{ name: 'Wi-Fi', description: 'Complimentary high-speed access.' }]
      });
    expect(roomTypeResponse.status).toBe(201);
    expect(roomTypeResponse.body.roomType.amenityDetails).toEqual([
      { name: 'Wi-Fi', description: 'Complimentary high-speed access.' }
    ]);
    const categories = await request(app).get(`/api/v1/agents/room-types/${property.id}`)
      .set(authorization(agent));
    expect(categories.body.roomTypes[0].amenityDetails).toEqual(
      roomTypeResponse.body.roomType.amenityDetails
    );
    const updated = await request(app).put(
      `/api/v1/agents/room-types/${roomTypeResponse.body.roomType.id}`
    ).set(authorization(agent)).send({
      amenityDetails: [{ name: 'Wi-Fi', description: 'Updated access details.' }]
    });
    expect(updated.status).toBe(200);
    expect(updated.body.roomType.amenityDetails[0].description).toBe('Updated access details.');
  });

  test('agents can create a persistent draft without publishing it', async () => {
    const response = await request(app).post('/api/v1/properties')
      .set(authorization(agent)).send({
        name: 'Saved Draft Hotel', city: 'Arusha', neighborhood: 'Central',
        priceTzs: 100000, businessModel: 'bookable', category: 'hotel',
        accommodationType: 'hotel', imageUrl: 'https://example.invalid/draft.jpg',
        bedrooms: 1, bathrooms: 1, description: 'A draft awaiting more information.',
        managerName: 'Stay Agent', saveAsDraft: true
      });
    expect(response.status).toBe(201);
    expect(response.body.property.listingStatus).toBe('draft');
    expect((await Property.findByPk(response.body.property.id)).listingStatus).toBe('draft');
  });

  test('walk-in creation rechecks property ownership inside the transaction', async () => {
    const property = await createProperty('Transferred Hotel');
    const type = await createRoomType(property.id);
    const room = await Room.create({
      propertyId: property.id, roomNumber: '101', roomTypeId: type.id
    });
    const stale = await Property.findByPk(property.id);
    await property.update({ agentId: admin.id });
    const lookup = jest.spyOn(Property, 'findByPk').mockResolvedValueOnce(stale);
    try {
      const response = await request(app)
        .post(`/api/v1/agents/walk-ins/${property.id}`)
        .set(authorization(agent)).send({
          requestKey: 'transferred-property', roomId: room.id, guestName: 'Guest Name',
          ...futureDates(), priceTzs: 10000, paymentStatus: 'unpaid'
        });
      expect(response.status).toBe(409);
      expect(await WalkInReservation.count({ where: { propertyId: property.id } })).toBe(0);
    } finally {
      lookup.mockRestore();
    }
  });

  test('legacy hotels without an accommodation type still require assigned rooms to publish', async () => {
    const legacy = await createProperty('Legacy Hotel');
    await legacy.update({ accommodationType: null, listingStatus: 'draft', latitude: -3, longitude: 36 });
    const result = await request(app).patch(`/api/v1/properties/${legacy.id}/status`)
      .set(authorization(admin)).send({ status: 'published' });
    expect(result.status).toBe(400);
    expect(result.body.error).toMatch(/assign/i);
  });

  test('hotels cannot be booked without a category or without assigned physical rooms', async () => {
    const type = await createRoomType(hotel.id);
    const dates = futureDates();
    const noCategory = await request(app).post('/api/v1/bookings')
      .set(authorization(firstCustomer))
      .send({ propertyId: hotel.id, requestKey: 'no-category', ...dates, guestName: 'First Guest' });
    expect(noCategory.status).toBe(400);
    const noRooms = await createBooking(firstCustomer, hotel, type, 'no-assigned-room', dates);
    expect(noRooms.status).toBe(409);
    const availability = await request(app).get('/api/v1/bookings/availability/check')
      .query({ propertyId: hotel.id, roomTypeId: type.id, ...dates });
    expect(availability.body).toMatchObject({ available: false, availableRooms: 0 });
    await type.destroy();
  });

  test('generates 100 rooms across five floors and rejects duplicate room numbers', async () => {
    const floors = Array.from({ length: 5 }, (_, index) => ({
      label: `Floor ${index + 1}`,
      roomCount: 20,
      startNumber: (index + 1) * 100 + 1
    }));
    const generated = await request(app)
      .post(`/api/v1/agents/rooms/${hotel.id}/generate`)
      .set(authorization(agent))
      .send({ floors });

    expect(generated.status).toBe(201);
    expect(generated.body.rooms).toBe(100);
    expect(await Room.count({ where: { propertyId: hotel.id } })).toBe(100);

    const collision = await request(app)
      .post(`/api/v1/agents/rooms/${motel.id}/generate`)
      .set(authorization(agent))
      .send({
        floors: [
          { label: 'Ground', roomCount: 2, startNumber: 1 },
          { label: 'Upper', roomCount: 2, startNumber: 1 }
        ]
      });
    expect(collision.status).toBe(400);
    expect(await Room.count({ where: { propertyId: motel.id } })).toBe(0);
    const invalid = await request(app).post(`/api/v1/agents/rooms/${motel.id}/generate`)
      .set(authorization(agent)).send({
        floors: [{ label: 'Ground', roomCount: 2, roomNumbers: [' A01 ', 'a01'] }]
      });
    expect(invalid.status).toBe(400);
    expect(await Room.count({ where: { propertyId: motel.id } })).toBe(0);
  });

  test('assigns categories in bulk and enforces capacity and concurrent availability', async () => {
    const generated = await request(app)
      .post(`/api/v1/agents/rooms/${motel.id}/generate`)
      .set(authorization(agent))
      .send({ floors: [{ label: 'Ground floor', roomCount: 1, startNumber: 7 }] });
    expect(generated.status).toBe(201);

    roomType = await createRoomType(motel.id);
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const assigned = await request(app)
      .post('/api/v1/agents/rooms/assign')
      .set(authorization(agent))
      .send({ listingId: motel.id, roomTypeId: roomType.id, roomIds: [room.id] });
    expect(assigned.status).toBe(200);
    expect(assigned.body.assignedCount).toBe(1);

    const dates = futureDates();
    const tooManyGuests = await createBooking(
      firstCustomer,
      motel,
      roomType,
      'over-capacity',
      dates,
      3
    );
    expect(tooManyGuests.status).toBe(400);

    const results = await Promise.all([
      createBooking(firstCustomer, motel, roomType, 'concurrent-one', dates),
      createBooking(secondCustomer, motel, roomType, 'concurrent-two', dates)
    ]);
    expect(results.map((result) => result.status).sort()).toEqual([201, 409]);
    const created = results.find((result) => result.status === 201);
    expect(created.body.booking.assignedRoomNumber).toBe('7');
    expect(await Booking.count({
      where: { propertyId: motel.id, assignedRoomId: room.id, status: 'pending' }
    })).toBe(1);
    await Booking.update(
      { status: 'cancelled' },
      { where: { propertyId: motel.id, assignedRoomId: room.id, status: 'pending' } }
    );
  });

  test('expired pending holds do not prevent a later booking', async () => {
    const first = await createBooking(
      firstCustomer,
      motel,
      roomType,
      'hold-expiring',
      futureDates()
    );
    expect(first.status).toBe(201);
    await Booking.update(
      { holdExpiresAt: new Date(Date.now() - 60_000) },
      { where: { id: first.body.booking.id } }
    );
    const replacement = await createBooking(
      secondCustomer,
      motel,
      roomType,
      'after-expiry',
      futureDates()
    );
    expect(replacement.status).toBe(201);
    expect(replacement.body.booking.assignedRoomNumber).toBe('7');
    await Booking.update(
      { status: 'cancelled' },
      { where: { id: replacement.body.booking.id } }
    );
  });

  test('category reassignment cannot race a booking hold', async () => {
    const alternative = await createRoomType(motel.id);
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const assign = request(app).post('/api/v1/agents/rooms/assign')
      .set(authorization(agent))
      .send({ listingId: motel.id, roomTypeId: alternative.id, roomIds: [room.id] });
    const book = createBooking(firstCustomer, motel, roomType, 'assignment-race', futureDates());
    const [assignment, reservation] = await Promise.all([assign, book]);
    expect(
      (assignment.status === 200 && reservation.status === 409) ||
      (assignment.status === 409 && reservation.status === 201)
    ).toBe(true);
    if (reservation.status === 201) {
      expect((await room.reload()).roomTypeId).toBe(roomType.id);
      await Booking.update({ status: 'cancelled' }, { where: { id: reservation.body.booking.id } });
    }
    await room.reload();
    await room.update({ roomTypeId: roomType.id });
    await alternative.destroy();
  });

  test('category edits preserve active reservation capacity and category history', async () => {
    const dates = futureDates();
    const reservation = await createBooking(firstCustomer, motel, roomType, 'category-edit-hold', dates);
    expect(reservation.status).toBe(201);
    const update = (payload) => request(app).put(`/api/v1/agents/room-types/${roomType.id}`)
      .set(authorization(agent)).send(payload);
    expect((await update({ capacity: 1 })).status).toBe(409);
    expect((await update({ totalRooms: 0 })).status).toBe(400);
    const price = await update({ nightlyPriceTzs: 180000 });
    expect(price.status).toBe(200);
    expect((await Booking.findByPk(reservation.body.booking.id)).subtotalTzs)
      .toBe(reservation.body.booking.subtotalTzs);
    expect((await request(app).delete(`/api/v1/agents/room-types/${roomType.id}`)
      .set(authorization(agent))).status).toBe(409);
    await roomType.update({ nightlyPriceTzs: 120000 });
    await Booking.update({ status: 'cancelled' }, { where: { id: reservation.body.booking.id } });
  });

  test('concurrent category assignments respect the planned room count', async () => {
    const category = await createRoomType(hotel.id);
    const rooms = await Room.findAll({ where: { propertyId: hotel.id }, limit: 2 });
    const assign = (room) => request(app).post('/api/v1/agents/rooms/assign')
      .set(authorization(agent))
      .send({ listingId: hotel.id, roomTypeId: category.id, roomIds: [room.id] });
    const results = await Promise.all(rooms.map(assign));
    expect(results.map((result) => result.status).sort()).toEqual([200, 400]);
    expect(await Room.count({ where: { roomTypeId: category.id } })).toBe(1);
    await Room.update({ roomTypeId: null }, { where: { roomTypeId: category.id } });
    await category.destroy();
  });

  test('maintenance blocks prevent booking and cannot invalidate active holds', async () => {
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const dates = futureDates();
    const startDate = dates.checkIn.slice(0, 10);
    const endDate = dates.checkOut.slice(0, 10);
    const activeBooking = await createBooking(
      firstCustomer,
      motel,
      roomType,
      'maintenance-existing-hold',
      dates
    );
    expect(activeBooking.status).toBe(201);
    const blocked = await request(app)
      .post(`/api/v1/agents/rooms/${motel.id}/${room.id}/blocks`)
      .set(authorization(agent))
      .send({ startDate, endDate, reason: 'Scheduled maintenance' });
    expect(blocked.status).toBe(409);
    await Booking.update(
      { status: 'cancelled' },
      { where: { id: activeBooking.body.booking.id } }
    );

    const maintenanceBlock = await request(app)
      .post(`/api/v1/agents/rooms/${motel.id}/${room.id}/blocks`)
      .set(authorization(agent))
      .send({ startDate, endDate, reason: 'Scheduled maintenance' });
    expect(maintenanceBlock.status).toBe(201);
    const calendar = await request(app)
      .get(`/api/v1/agents/rooms/${motel.id}/calendar`).set(authorization(agent))
      .query({ start: startDate, end: endDate });
    expect(calendar.status).toBe(200);
    expect(calendar.body.rooms[0].events).toEqual([
      expect.objectContaining({ kind: 'blocked', id: maintenanceBlock.body.block.id })
    ]);

    const availability = await request(app).get('/api/v1/bookings/availability/check')
      .query({
        propertyId: motel.id,
        roomTypeId: roomType.id,
        checkIn: dates.checkIn,
        checkOut: dates.checkOut
      });
    expect(availability.body).toMatchObject({
      available: false,
      availableRooms: 0
    });

    const rejected = await createBooking(
      firstCustomer,
      motel,
      roomType,
      'maintenance-conflict',
      dates
    );
    expect(rejected.status).toBe(409);

    const removed = await request(app)
      .delete(`/api/v1/agents/rooms/${motel.id}/${room.id}/blocks/${maintenanceBlock.body.block.id}`)
      .set(authorization(agent));
    expect(removed.status).toBe(200);
    expect(await RoomAvailabilityBlock.count({ where: { roomId: room.id } })).toBe(0);
  });

  test('payment verification cannot confirm a room removed from service', async () => {
    const dates = futureDates();
    const created = await createBooking(firstCustomer, motel, roomType, 'inactive-room-payment', dates);
    expect(created.status).toBe(201);
    const booking = await Booking.findByPk(created.body.booking.id);
    const room = await Room.findByPk(booking.assignedRoomId);
    const payment = await PaymentTransaction.create({
      reference: 'inactive-room-payment', purpose: 'accommodationBooking',
      amountTzs: booking.totalTzs, methodId: 'test', customerId: firstCustomer.id,
      bookingId: booking.id, status: 'pending'
    });
    await booking.update({ paymentTransactionId: payment.id });
    await room.update({ status: 'outOfService' });
    jest.spyOn(paymentService, 'isConfigured').mockReturnValue(true);
    jest.spyOn(paymentService, 'verifyTransaction').mockImplementation(async () => {
      await payment.update({ status: 'succeeded', verifiedAt: new Date() });
      return payment;
    });
    try {
      const verified = await request(app)
        .post(`/api/v1/payments/transactions/${payment.id}/verify`)
        .set(authorization(firstCustomer));
      expect(verified.status).toBe(409);
      expect((await Booking.findByPk(booking.id)).status).toBe('pending');
    } finally {
      jest.restoreAllMocks();
      await room.update({ status: 'active' });
      await booking.update({ status: 'cancelled' });
    }
  });

  test('walk-ins share holds, availability, maintenance and audited lifecycle', async () => {
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const dates = futureDates();
    const createWalkIn = (data) => request(app).post(`/api/v1/agents/walk-ins/${motel.id}`)
      .set(authorization(agent)).send({
        requestKey: 'walk-in-first', roomId: room.id, guestName: 'Walk In Guest',
        ...dates, priceTzs: 80000, paymentStatus: 'unpaid', ...data
      });
    const online = await createBooking(firstCustomer, motel, roomType, 'walkin-online-hold', dates);
    expect(online.status).toBe(201);
    const calendarQuery = { start: dates.checkIn.slice(0, 10), end: dates.checkOut.slice(0, 10) };
    const calendar = () => request(app).get(`/api/v1/agents/rooms/${motel.id}/calendar`)
      .set(authorization(agent)).query(calendarQuery);
    const held = await calendar();
    expect(held.status).toBe(200);
    expect(held.body.rooms[0]).toMatchObject({ occupancy: 'vacant', events: [expect.objectContaining({ kind: 'hold' })] });
    expect((await request(app).get(`/api/v1/agents/rooms/${motel.id}/calendar`)
      .set(authorization(firstCustomer)).query(calendarQuery)).status).toBe(403);
    expect((await request(app).get(`/api/v1/agents/rooms/${motel.id}/calendar`)
      .set(authorization(agent)).query({ start: '2026-01-01', end: '2027-01-01' })).status).toBe(400);
    expect((await createWalkIn()).status).toBe(409);
    await Booking.update({ status: 'cancelled' }, { where: { id: online.body.booking.id } });
    const created = await createWalkIn();
    expect(created.status).toBe(201);
    const walkIn = created.body.reservation;
    expect(walkIn.status).toBe('reserved');
    expect((await calendar()).body.rooms[0]).toMatchObject({
      occupancy: 'vacant', events: [expect.objectContaining({ kind: 'walkIn', id: walkIn.id })]
    });
    expect((await createWalkIn()).body.reservation.id).toBe(walkIn.id);
    expect((await createWalkIn({ guestName: 'Another Guest' })).status).toBe(409);
    expect((await createBooking(firstCustomer, motel, roomType, 'walkin-conflict', dates)).status).toBe(409);
    for (const query of [{ ...dates }, { ...dates, roomTypeId: roomType.id }]) {
      const available = await request(app).get('/api/v1/bookings/availability/check')
        .query({ propertyId: motel.id, ...query });
      expect(available.body.available).toBe(false);
    }
    const blocked = await request(app)
      .post(`/api/v1/agents/rooms/${motel.id}/${room.id}/blocks`).set(authorization(agent))
      .send({ startDate: dates.checkIn.slice(0, 10), endDate: dates.checkOut.slice(0, 10), reason: 'Repair' });
    expect(blocked.status).toBe(409);
    const assign = await request(app).post('/api/v1/agents/rooms/assign').set(authorization(agent))
      .send({ listingId: motel.id, roomTypeId: roomType.id, roomIds: [room.id] });
    expect(assign.status).toBe(409);
    const payment = await request(app).post(`/api/v1/agents/walk-ins/${motel.id}/${walkIn.id}/payment`)
      .set(authorization(agent)).send({ paymentStatus: 'paid' });
    expect(payment.status).toBe(200);
    const oversight = await request(app).get('/api/v1/admin/room-inventory').set(authorization(admin));
    expect(oversight.status).toBe(200);
    const entry = oversight.body.inventory.find((item) => item.property.id === motel.id);
    expect(entry.walkIns).toEqual([
      expect.objectContaining({ id: walkIn.id, guestName: 'Walk In Guest', paymentStatus: 'paid' })
    ]);
    expect(entry.walkIns[0].guestPhone).toBeUndefined();
    expect((await request(app).get('/api/v1/admin/room-inventory').set(authorization(agent))).status).toBe(403);
    expect((await createWalkIn()).status).toBe(200);
    const cancel = await request(app).post(`/api/v1/agents/walk-ins/${motel.id}/${walkIn.id}/cancel`)
      .set(authorization(agent)).send({ reason: 'Guest cancelled' });
    expect(cancel.status).toBe(200);
    expect((await WalkInReservation.findByPk(walkIn.id)).status).toBe('cancelled');
    expect(await AdminAuditEvent.count({ where: { entityType: 'WalkInReservation', entityId: walkIn.id } })).toBe(3);
    expect((await createBooking(firstCustomer, motel, roomType, 'walkin-after-cancel', dates)).status).toBe(201);
    await Booking.update({ status: 'cancelled' }, { where: { requestKey: 'walkin-after-cancel' } });
  });

  test('online bookings and walk-ins cannot simultaneously reserve the last room', async () => {
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const dates = futureDates();
    const walkIn = request(app).post(`/api/v1/agents/walk-ins/${motel.id}`)
      .set(authorization(agent)).send({
        requestKey: 'walk-in-race', roomId: room.id, guestName: 'Walk In Guest',
        ...dates, priceTzs: 80000, paymentStatus: 'unpaid'
      });
    const online = createBooking(firstCustomer, motel, roomType, 'walk-in-race-online', dates);
    const results = await Promise.all([walkIn, online]);
    expect(results.map((result) => result.status).sort()).toEqual([201, 409]);
    await WalkInReservation.update({ status: 'cancelled' }, { where: { requestKey: 'walk-in-race' } });
    await Booking.update({ status: 'cancelled' }, { where: { requestKey: 'walk-in-race-online' } });
  });

  test('walk-in conflicts suggest only eligible available rooms in the category', async () => {
    const lodge = await createProperty('Alternatives Lodge', 'lodge');
    const type = await createRoomType(lodge.id, 2);
    const first = await Room.create({ propertyId: lodge.id, roomNumber: 'A01', roomTypeId: type.id });
    await Room.create({ propertyId: lodge.id, roomNumber: 'VIP-B', roomTypeId: type.id });
    const dates = futureDates();
    expect((await createBooking(firstCustomer, lodge, type, 'suggestion-hold', dates)).status).toBe(201);
    const conflict = await request(app).post(`/api/v1/agents/walk-ins/${lodge.id}`)
      .set(authorization(agent)).send({
        requestKey: 'suggestion-walkin', roomId: first.id, guestName: 'Walk In Guest',
        ...dates, priceTzs: 80000, paymentStatus: 'unpaid'
      });
    expect(conflict.status).toBe(409);
    expect(conflict.body.error).toContain('VIP-B');
  });

  test('walk-in checkout preserves history and cannot be performed by an unrelated customer', async () => {
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const now = Date.now();
    const payload = {
      requestKey: 'walk-in-checkout', roomId: room.id, guestName: 'Walk In Guest',
      checkIn: new Date(now - 1000).toISOString(),
      checkOut: new Date(now + 86400000).toISOString(),
      priceTzs: 90000, paymentStatus: 'paid', checkInNow: true
    };
    const created = await request(app).post(`/api/v1/agents/walk-ins/${motel.id}`)
      .set(authorization(agent)).send(payload);
    expect(created.status).toBe(201);
    const id = created.body.reservation.id;
    const url = `/api/v1/agents/walk-ins/${motel.id}/${id}/checkout`;
    expect((await request(app).post(url).set(authorization(firstCustomer))).status).toBe(403);
    expect((await request(app).post(url).set(authorization(agent))).status).toBe(200);
    const stored = await WalkInReservation.findByPk(id);
    expect(stored.status).toBe('completed');
    expect(stored.checkedInAt).not.toBeNull();
    expect(stored.checkedOutAt).not.toBeNull();
    expect((await request(app).post(url).set(authorization(agent))).status).toBe(409);
  });

  test('walk-in extension cannot displace an adjacent online hold or delete it on checkout', async () => {
    const room = await Room.findOne({ where: { propertyId: motel.id } });
    const now = Date.now();
    const next = new Date(now + 86400000);
    const end = new Date(now + 2 * 86400000);
    const walkIn = await request(app).post(`/api/v1/agents/walk-ins/${motel.id}`)
      .set(authorization(agent)).send({
        requestKey: 'walkin-extension', roomId: room.id, guestName: 'Walk In Guest',
        checkIn: new Date(now - 1000).toISOString(), checkOut: next.toISOString(),
        priceTzs: 90000, paymentStatus: 'unpaid', checkInNow: true
      });
    expect(walkIn.status).toBe(201);
    const nextBooking = await createBooking(firstCustomer, motel, roomType, 'after-walkin',
      { checkIn: next.toISOString(), checkOut: end.toISOString() });
    expect(nextBooking.status).toBe(201);
    const extension = await request(app)
      .post(`/api/v1/agents/walk-ins/${motel.id}/${walkIn.body.reservation.id}/extend`)
      .set(authorization(agent)).send({ checkOut: end.toISOString() });
    expect(extension.status).toBe(409);
    const checkout = await request(app)
      .post(`/api/v1/agents/walk-ins/${motel.id}/${walkIn.body.reservation.id}/checkout`)
      .set(authorization(agent));
    expect(checkout.status).toBe(200);
    expect((await Booking.findByPk(nextBooking.body.booking.id)).status).toBe('pending');
    expect((await WalkInReservation.findByPk(walkIn.body.reservation.id)).status).toBe('completed');
    await Booking.update({ status: 'cancelled' }, { where: { id: nextBooking.body.booking.id } });
  });

  test('checked-in room changes preserve segmented occupancy and require an audited reason', async () => {
    const lodge = await createProperty('Room Move Lodge', 'lodge');
    const type = await createRoomType(lodge.id, 3);
    const [oldRoom, newRoom, spareRoom] = await Promise.all(['A01', 'A02', 'A03'].map((roomNumber) =>
      Room.create({ propertyId: lodge.id, roomNumber, roomTypeId: type.id })
    ));
    const now = Date.now();
    const checkIn = new Date(now - 60000);
    const checkOut = new Date(now + 86400000);
    const created = await request(app).post(`/api/v1/agents/walk-ins/${lodge.id}`)
      .set(authorization(agent)).send({
        requestKey: 'segmented-room-move', roomId: oldRoom.id,
        guestName: 'Walk In Guest', checkIn: checkIn.toISOString(),
        checkOut: checkOut.toISOString(), priceTzs: 90000,
        paymentStatus: 'unpaid', checkInNow: true
      });
    expect(created.status).toBe(201);
    const id = created.body.reservation.id;
    const move = () => request(app)
      .post(`/api/v1/agents/walk-ins/${lodge.id}/${id}/change-room`)
      .set(authorization(agent)).send({ roomId: newRoom.id, reason: 'Room maintenance' });
    const missingReason = await request(app)
      .post(`/api/v1/agents/walk-ins/${lodge.id}/${id}/change-room`)
      .set(authorization(agent)).send({ roomId: spareRoom.id });
    expect(missingReason.status).toBe(400);

    expect((await move()).status).toBe(200);
    const segments = await WalkInRoomSegment.findAll({
      where: { walkInReservationId: id }, order: [['startAt', 'ASC']]
    });
    expect(segments).toHaveLength(2);
    expect(segments[0].roomId).toBe(oldRoom.id);
    expect(segments[0].endAt.getTime()).toBe(segments[1].startAt.getTime());
    expect(segments[1].roomId).toBe(newRoom.id);

    const afterMove = new Date(segments[1].startAt.getTime() + 1000);
    expect(await unavailableRoomIds([oldRoom.id], afterMove, checkOut)).not.toContain(oldRoom.id);
    expect(await unavailableRoomIds([newRoom.id], afterMove, checkOut)).toContain(newRoom.id);
    expect(await unavailableRoomIds(
      [newRoom.id], checkIn, new Date(segments[1].startAt.getTime() - 1)
    )).not.toContain(newRoom.id);

    const listed = await request(app).get(`/api/v1/agents/walk-ins/${lodge.id}`)
      .set(authorization(agent));
    expect(listed.status).toBe(200);
    expect(listed.body.reservations[0].roomSegments).toHaveLength(2);
    expect(await AdminAuditEvent.count({
      where: { entityType: 'WalkInReservation', entityId: id, action: 'WALK_IN_CHANGE_ROOM' }
    })).toBe(1);

    const calendarStart = checkIn.toISOString().slice(0, 10);
    const calendarEnd = new Date(checkOut.getTime() + 86400000).toISOString().slice(0, 10);
    const calendar = await request(app)
      .get(`/api/v1/agents/rooms/${lodge.id}/calendar?start=${calendarStart}&end=${calendarEnd}`)
      .set(authorization(agent));
    expect(calendar.status).toBe(200);
    expect(calendar.body.rooms.find((room) => room.id === oldRoom.id).events)
      .toEqual(expect.arrayContaining([expect.objectContaining({ id, kind: 'walkIn' })]));
    expect(calendar.body.rooms.find((room) => room.id === newRoom.id).events)
      .toEqual(expect.arrayContaining([expect.objectContaining({ id, kind: 'walkIn' })]));
    expect(calendar.body.rooms.find((room) => room.id === oldRoom.id).occupancy).toBe('vacant');
    expect(calendar.body.rooms.find((room) => room.id === newRoom.id).occupancy).toBe('checkedIn');

    await WalkInRoomSegment.destroy({ where: { walkInReservationId: id } });
    await syncDatabase();
    expect(await WalkInRoomSegment.count({ where: { walkInReservationId: id } })).toBe(1);
    await syncDatabase();
    expect(await WalkInRoomSegment.count({ where: { walkInReservationId: id } })).toBe(1);
  });

  test('blocks publication until every active room has a category', async () => {
    await Room.update({ roomTypeId: null }, { where: { propertyId: hotel.id } });
    const response = await request(app)
      .patch(`/api/v1/properties/${hotel.id}/status`)
      .set(authorization(admin))
      .send({ status: 'published' });
    expect(response.status).toBe(400);
  });
});
