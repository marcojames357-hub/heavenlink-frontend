'use strict';

// Deliberately separate from the legacy seeds, which update existing accounts.
// This tool can create only this backend's isolated, explicitly named demo DB.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sqlite3 = require('sqlite3');
require('dotenv').config();

const DATASET = 'havenlink-local-demo-v1';
const DEMO_DATABASE = path.resolve(__dirname, '../data/havenlink-demo.sqlite');
const MARKER_TABLE = 'HavenLocalDemoSeed';
const DEMO_PASSWORD = 'HavenDemo!2026';

function demoId(key) {
  const hex = crypto.createHash('sha256').update(`${DATASET}:${key}`).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

const accounts = [
  { key: 'customer', fullName: 'Amina Mhando (Demo)', email: 'customer@demo.havenlink.test', phone: '+255700900001', role: 'CUSTOMER', capabilities: [], workspaces: [] },
  { key: 'rental', fullName: 'Juma Rental Agent (Demo)', email: 'rental@demo.havenlink.test', phone: '+255700900002', role: 'RENTAL_AGENT', capabilities: ['rentalProperty'], workspaces: ['RENTAL'] },
  { key: 'apartment', fullName: 'Neema Apartment Host (Demo)', email: 'apartment@demo.havenlink.test', phone: '+255700900003', role: 'STAY_AGENT', capabilities: ['accommodationBooking'], workspaces: ['APARTMENT'] },
  { key: 'hotel', fullName: 'Baraka Stay Manager (Demo)', email: 'hotel@demo.havenlink.test', phone: '+255700900004', role: 'STAY_AGENT', capabilities: ['accommodationBooking'], workspaces: ['HOTEL'] },
  { key: 'admin', fullName: 'Haven Link Administrator (Demo)', email: 'admin@demo.havenlink.test', phone: '+255700900005', role: 'ADMIN', capabilities: [], workspaces: [] }
].map((account) => ({ ...account, id: demoId(`user:${account.key}`) }));

const photo = (id) => `https://images.unsplash.com/${id}?auto=format&fit=crop&w=1200&q=85`;
const photos = {
  home: photo('photo-1657635495653-72d14e0c2f06'),
  apartment: photo('photo-1502672260266-1c1ef2d93688'),
  interior: photo('photo-1493809842364-78817add7ffb'),
  lodge: photo('photo-1768047845974-a1830dfb186a'),
  hotel: photo('photo-1637010111726-5a8bf4c6d8f5'),
  room: photo('photo-1611892440504-42a792e24d32'),
  beach: photo('photo-1768047846080-d477e260ff00')
};

const properties = [
  { key: 'masaki-home', agent: 'rental', name: 'Masaki Garden Home', model: 'contactUnlock', category: 'house', city: 'Dar es Salaam', neighborhood: 'Masaki', latitude: -6.7511, longitude: 39.2825, price: 850000, bedrooms: 3, bathrooms: 2, image: photos.home, amenities: ['Garden', 'Parking', 'Water tank', 'Security'], description: 'A three-bedroom garden home with secure parking and a covered veranda. This fictional listing demonstrates monthly rental discovery and protected contact access.' },
  { key: 'mbezi-home', agent: 'rental', name: 'Mbezi Beach Family House', model: 'contactUnlock', category: 'house', city: 'Dar es Salaam', neighborhood: 'Mbezi Beach', latitude: -6.6718, longitude: 39.2194, price: 650000, bedrooms: 2, bathrooms: 2, image: photos.beach, amenities: ['Parking', 'Water tank', 'Garden', 'Electricity'], description: 'A bright two-bedroom family home with a private compound. This fictional demo rental keeps its exact address and contact behind the existing payment-authorized unlock.' },
  { key: 'sinza-room', agent: 'rental', name: 'Sinza Private Room', model: 'contactUnlock', category: 'room', city: 'Dar es Salaam', neighborhood: 'Sinza', latitude: -6.7886, longitude: 39.2294, price: 180000, bedrooms: 1, bathrooms: 1, image: photos.room, amenities: ['Water', 'Electricity', 'Security'], description: 'A private room with convenient transport connections and access to water. A fictional monthly-rental example for comparing room and house listings.' },
  { key: 'masaki-apartment', agent: 'apartment', name: 'Masaki Sea View Apartment', model: 'bookable', category: 'shortStayApartment', city: 'Dar es Salaam', neighborhood: 'Masaki', latitude: -6.7456, longitude: 39.2810, price: 220000, bedrooms: 2, bathrooms: 2, maxGuests: 4, image: photos.apartment, amenities: ['WiFi', 'Kitchen', 'Air conditioning', 'Parking', 'Balcony'], description: 'A whole-unit, two-bedroom apartment with a kitchen and balcony. This fictional short stay demonstrates apartment availability, guest limits and booking details.' },
  { key: 'arusha-apartment', agent: 'apartment', name: 'Arusha Garden Residence', model: 'bookable', category: 'servicedApartment', city: 'Arusha', neighborhood: 'Njiro', latitude: -3.3869, longitude: 36.6830, price: 180000, bedrooms: 3, bathrooms: 2, maxGuests: 6, image: photos.interior, amenities: ['WiFi', 'Kitchen', 'Garden', 'Parking', 'Hot water'], description: 'A serviced three-bedroom apartment in a quiet garden compound, booked as one unit. Fictional demo accommodation for families and small groups.' },
  { key: 'zanzibar-apartment', agent: 'apartment', name: 'Stone Town Heritage Apartment', model: 'bookable', category: 'shortStayApartment', city: 'Zanzibar', neighborhood: 'Stone Town', latitude: -6.1659, longitude: 39.1925, price: 150000, bedrooms: 1, bathrooms: 1, maxGuests: 2, image: photos.beach, amenities: ['WiFi', 'Kitchen', 'Air conditioning', 'Terrace'], description: 'A one-bedroom entire apartment with a terrace and kitchen. This fictional demo stay illustrates a compact whole-unit booking experience.' },
  { key: 'arusha-hotel', agent: 'hotel', name: 'Serengeti View Hotel', model: 'bookable', category: 'hotel', accommodationType: 'hotel', city: 'Arusha', neighborhood: 'Njiro', latitude: -3.3869, longitude: 36.6830, price: 125000, bedrooms: 4, bathrooms: 4, image: photos.hotel, amenities: ['WiFi', 'Restaurant', 'Pool', 'Parking', 'Breakfast'], description: 'A fictional hotel with standard and family rooms, a restaurant and a pool. Demo room categories are connected to individual physical rooms.' },
  { key: 'zanzibar-hotel', agent: 'hotel', name: 'Zanzibar Palm Beach Hotel', model: 'bookable', category: 'hotel', accommodationType: 'hotel', city: 'Zanzibar', neighborhood: 'Nungwi', latitude: -5.7258, longitude: 39.2994, price: 210000, bedrooms: 4, bathrooms: 4, image: photos.beach, amenities: ['WiFi', 'Restaurant', 'Beach access', 'Pool', 'Air conditioning'], description: 'A fictional beach hotel with individual room inventory. Use its demo room categories to inspect reservation, room and availability screens.' },
  { key: 'serengeti-lodge', agent: 'hotel', name: 'Serengeti View Lodge', model: 'bookable', category: 'lodge', accommodationType: 'lodge', city: 'Karatu', neighborhood: 'Rhotia', latitude: -3.3287, longitude: 35.6680, price: 175000, bedrooms: 4, bathrooms: 4, image: photos.lodge, amenities: ['WiFi', 'Restaurant', 'Garden', 'Parking', 'Breakfast'], description: 'A fictional lodge with private standard and family cottages. Demo room assignment uses the same physical-room architecture as hotels.' },
  // The backend's existing motel representation is category=hotel plus the
  // accommodationType discriminator; do not change its schema for demo data.
  { key: 'moshi-motel', agent: 'hotel', name: 'Kilimanjaro Road Motel', model: 'bookable', category: 'hotel', accommodationType: 'motel', city: 'Moshi', neighborhood: 'Kiboriloni', latitude: -3.3500, longitude: 37.3333, price: 60000, bedrooms: 4, bathrooms: 4, image: photos.hotel, amenities: ['WiFi', 'Parking', 'Hot water', 'Security'], description: 'A fictional roadside motel with secure parking and individual room inventory. Motel routing uses the existing accommodation-type discriminator.' }
].map((property) => ({ ...property, id: demoId(`property:${property.key}`) }));

function resolveTarget(input) {
  if (process.env.NODE_ENV === 'production') throw new Error('Demo seeding is disabled in production.');
  const requested = path.resolve(input || DEMO_DATABASE);
  if (requested.toLowerCase() !== DEMO_DATABASE.toLowerCase()) {
    throw new Error(`Refusing target: demo seeding is limited to ${DEMO_DATABASE}`);
  }
  const directory = path.dirname(requested);
  if (!fs.existsSync(directory) || fs.lstatSync(directory).isSymbolicLink()) {
    throw new Error('The backend data directory must exist and must not be a symbolic link.');
  }
  const realDirectory = fs.realpathSync(directory);
  if (realDirectory.toLowerCase() !== directory.toLowerCase()) {
    throw new Error('Refusing a redirected demo data directory.');
  }
  if (fs.existsSync(requested)) {
    const stat = fs.lstatSync(requested);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink > 1) {
      throw new Error('Refusing a linked or non-file database target.');
    }
  }
  return requested;
}

const sqlAll = (db, sql, params = []) => new Promise((resolve, reject) => db.all(sql, params, (error, rows) => error ? reject(error) : resolve(rows)));
const sqlRun = (db, sql, params = []) => new Promise((resolve, reject) => db.run(sql, params, (error) => error ? reject(error) : resolve()));
const sqlClose = (db) => new Promise((resolve, reject) => db.close((error) => error ? reject(error) : resolve()));
const sqlOpen = (file, flags) => new Promise((resolve, reject) => {
  const db = new sqlite3.Database(file, flags, (error) => error ? reject(error) : resolve(db));
});

async function inspectTarget(file, { strictFixtures = true } = {}) {
  if (!fs.existsSync(file) || fs.statSync(file).size === 0) return { exists: fs.existsSync(file), initialized: false };
  const db = await sqlOpen(file, sqlite3.OPEN_READONLY);
  try {
    const tables = await sqlAll(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    if (tables.length === 0) return { exists: true, initialized: false };
    if (!tables.some((table) => table.name === MARKER_TABLE)) {
      throw new Error('Refusing an existing database without the local-demo dataset marker.');
    }
    const markers = await sqlAll(db, `SELECT dataset FROM ${MARKER_TABLE}`);
    if (markers.length !== 1 || markers[0].dataset !== DATASET) throw new Error('Unexpected demo database marker.');
    if (strictFixtures && tables.some((table) => table.name === 'Users')) {
      const expected = new Map(accounts.map((account) => [account.id, account]));
      const rows = await sqlAll(db, 'SELECT id, email, phone, role FROM Users');
      if (rows.some((row) => {
        const account = expected.get(row.id);
        return !account || row.email !== account.email || row.phone !== account.phone || row.role !== account.role;
      })) throw new Error('Refusing to seed a demo database containing non-demo or reassigned user identities. Existing data is unchanged.');
    }
    if (strictFixtures && tables.some((table) => table.name === 'Properties')) {
      const expected = new Map(properties.map((property) => [property.id, demoId(`user:${property.agent}`)]));
      const rows = await sqlAll(db, 'SELECT id, agentId FROM Properties');
      if (rows.some((row) => expected.get(row.id) !== row.agentId)) {
        throw new Error('Refusing to seed a demo database containing non-demo or reassigned listings. Existing data is unchanged.');
      }
    }
    return { exists: true, initialized: tables.some((table) => table.name === 'Users') && tables.some((table) => table.name === 'Properties') };
  } finally {
    await sqlClose(db);
  }
}

async function validateRuntimeTarget(database) {
  const target = resolveTarget(database);
  const state = await inspectTarget(target, { strictFixtures: false });
  if (!state.initialized) throw new Error('Local demo database is absent or uninitialized. Run npm run seed:demo first.');
  return { database: target, ...state };
}

async function claimDemoDatabase(file) {
  const db = await sqlOpen(file, sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE);
  try {
    await sqlRun(db, `CREATE TABLE IF NOT EXISTS ${MARKER_TABLE} (dataset TEXT PRIMARY KEY, createdAt TEXT NOT NULL)`);
    await sqlRun(db, `INSERT OR IGNORE INTO ${MARKER_TABLE} (dataset, createdAt) VALUES (?, ?)`, [DATASET, new Date().toISOString()]);
  } finally {
    await sqlClose(db);
  }
}

async function seedDemo({ database, check = false } = {}) {
  const target = resolveTarget(database);
  const state = await inspectTarget(target);
  if (check) {
    if (!state.initialized) throw new Error('Local demo database is absent or uninitialized. Run npm run seed:demo first.');
    return { database: target, ...state, usersPlanned: accounts.length, propertiesPlanned: properties.length, writes: false };
  }
  await claimDemoDatabase(target);
  // Override any inherited/.env database path BEFORE importing Sequelize models.
  process.env.SQLITE_STORAGE = target;
  const models = require('./models');
  const { sequelize, syncDatabase, User, AgentWorkspace, AgentProfile, Property, OwnerContact, RoomType, Floor, Room, CheckInPolicy, SavedProperty } = models;
  if (path.resolve(sequelize.options.storage).toLowerCase() !== target.toLowerCase()) {
    throw new Error('Models were already loaded against another database. Run seed:demo in a separate Node process.');
  }
  try {
    await syncDatabase();
    await sequelize.transaction(async (transaction) => {
      const add = async (Model, where, defaults) => Model.findOrCreate({ where, defaults, transaction });
      for (const account of accounts) {
        await add(User, { id: account.id }, {
          fullName: account.fullName, email: account.email, phone: account.phone,
          password: DEMO_PASSWORD, role: account.role, capabilities: account.capabilities,
          verification: 'verified', accountEnabled: true
        });
        for (const workspace of account.workspaces) {
          await add(AgentWorkspace, { userId: account.id, workspace }, { id: demoId(`workspace:${account.key}:${workspace}`), status: 'active', source: 'demo' });
        }
        if (account.workspaces.length) await add(AgentProfile, { userId: account.id }, {
          agencyName: 'Haven Link Demo Workspace', bio: 'Fictional local demo account. No real owner or accommodation is represented.',
          serviceAreas: ['Dar es Salaam', 'Arusha', 'Zanzibar', 'Moshi', 'Karatu']
        });
      }
      for (const listing of properties) {
        const agent = accounts.find((account) => account.key === listing.agent);
        const isRental = listing.model === 'contactUnlock';
        const isApartment = listing.agent === 'apartment';
        const imageUrls = [...new Set([listing.image, isApartment ? photos.interior : photos.room])];
        await add(Property, { id: listing.id }, {
          name: `${listing.name} (Demo)`, city: listing.city, neighborhood: listing.neighborhood,
          latitude: listing.latitude, longitude: listing.longitude,
          formattedAddress: `Demo address, ${listing.neighborhood}, ${listing.city}, Tanzania`,
          locationVerification: 'verified', locationVisibility: 'approximate',
          priceTzs: listing.price, businessModel: listing.model, category: listing.category,
          accommodationType: listing.accommodationType || null,
          imageUrl: listing.image, imageUrls, rating: 0, reviewCount: 0,
          bedrooms: listing.bedrooms, bathrooms: listing.bathrooms, maxGuests: listing.maxGuests || null,
          stayRules: isApartment ? { minNights: 1, maxNights: 30, checkInTime: '14:00', checkOutTime: '11:00', beds: listing.bedrooms, country: 'Tanzania', houseRules: 'Demo property: no real accommodation is offered.', cancellationPolicy: 'Demonstration policy only; no real payment or reservation is accepted.' } : null,
          amenities: listing.amenities, description: `[DEMO] ${listing.description}`,
          available: true, furnished: !isRental, parking: listing.amenities.includes('Parking'),
          water: true, electricity: true, security: true, propertyVerification: 'verified', ownerVerification: 'verified',
          managerName: agent.fullName, listingStatus: 'published', rentalPeriod: isRental ? 'month' : 'day', agentId: agent.id
        });
        if (isRental) {
          await add(OwnerContact, { propertyId: listing.id }, {
            id: demoId(`contact:${listing.key}`), exactAddress: `FICTIONAL DEMO ADDRESS — ${listing.neighborhood}, ${listing.city}. Not a real listing.`,
            contactName: agent.fullName, role: 'Demo Rental Agent', phone: agent.phone, whatsApp: agent.phone,
            latitude: listing.latitude, longitude: listing.longitude
          });
        }
        if (listing.agent === 'hotel') {
          await add(CheckInPolicy, { listingId: listing.id }, {
            id: demoId(`policy:${listing.key}`), checkInFrom: '14:00', checkOutBy: '11:00', cancellationHours: 24,
            notes: 'Local demo policy. No real accommodation booking is offered.'
          });
          for (const [index, roomName] of ['Standard Room', 'Family Room'].entries()) {
            const floorId = demoId(`floor:${listing.key}:${index}`);
            const roomTypeId = demoId(`room-type:${listing.key}:${index}`);
            await add(Floor, { id: floorId }, { propertyId: listing.id, label: index === 0 ? 'Ground Floor' : 'First Floor', sortOrder: index });
            await add(RoomType, { id: roomTypeId }, {
              listingId: listing.id, name: roomName, nightlyPriceTzs: listing.price + index * 40000,
              currency: 'TZS', capacity: index === 0 ? 2 : 4, totalRooms: 2,
              amenities: ['Private bathroom', 'WiFi', 'Hot water'], imageUrls: [photos.room], primaryImageUrl: photos.room,
              bedType: index === 0 ? 'Double' : 'Two doubles', numberOfBeds: index + 1, bathroomType: 'Private',
              description: `${roomName} at ${listing.name}. Fictional local demo inventory.`
            });
            for (let number = 1; number <= 2; number += 1) await add(Room, { id: demoId(`room:${listing.key}:${index}:${number}`) }, {
              propertyId: listing.id, floorId, roomTypeId, roomNumber: `${index + 1}0${number}`, status: 'active'
            });
          }
        }
      }
      const customerId = demoId('user:customer');
      for (const key of ['masaki-home', 'masaki-apartment']) await add(SavedProperty, { customerId, listingId: demoId(`property:${key}`) }, { id: demoId(`saved:${key}`) });
    });
    return {
      database: target, users: await User.count(), properties: await Property.count(), roomTypes: await RoomType.count(),
      rooms: await Room.count(), paymentsSeeded: 0, reviewsSeeded: 0,
      note: 'Additive demo seed complete. Existing fixture data and passwords were not overwritten. Demo credentials are documented in docs/LOCAL_DEMO.md.'
    };
  } finally {
    await sequelize.close();
  }
}

function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === '--check') options.check = true;
    else if (args[index] === '--database' && args[index + 1]) options.database = args[++index];
    else if (args[index] === '--help') options.help = true;
    else throw new Error(`Unknown or incomplete argument: ${args[index]}`);
  }
  return options;
}

if (require.main === module) {
  (async () => {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      console.log('Usage: npm run seed:demo -- [--check] [--database data/havenlink-demo.sqlite]');
      console.log('Writes only this backend\'s isolated havenlink-demo.sqlite; refuses production and non-demo data. --check validates an existing initialized dataset without writes.');
      return;
    }
    console.log(JSON.stringify(await seedDemo(options), null, 2));
  })().catch((error) => { console.error(`Demo seed refused or failed: ${error.message}`); process.exitCode = 1; });
}

module.exports = { resolveTarget, inspectTarget, validateRuntimeTarget, seedDemo, demoId, accounts, properties, DATASET, DEMO_DATABASE };
