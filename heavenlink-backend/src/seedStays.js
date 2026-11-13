require('dotenv').config();
const { User, Property, RoomType, Floor, Room, syncDatabase } = require('./models');
const sequelize = require('./config/database');

const img = (id) => `https://images.unsplash.com/${id}?auto=format&fit=crop&w=1200&q=80`;

const stays = [
  {
    type: 'hotel', category: 'hotel', name: 'Serengeti Grand Hotel', city: 'Arusha', neighborhood: 'Njiro',
    lat: -3.3869, lng: 36.6830, price: 180000, rating: 4.6, reviews: 128,
    image: img('photo-1566073771259-6a8506099945'),
    amenities: ['WiFi', 'Pool', 'Restaurant', 'Air conditioning', 'Parking', 'Airport shuttle'],
    description: 'Four-star business and leisure hotel with a rooftop pool, restaurant and conference rooms, minutes from Arusha city centre.',
    floors: ['Ground Floor', 'First Floor', 'Second Floor'],
    roomTypes: [
      { name: 'Standard Room', price: 120000, capacity: 2, bed: 'Queen', rooms: [['101', 0], ['102', 0], ['201', 1], ['202', 1]] },
      { name: 'Deluxe Room', price: 180000, capacity: 3, bed: 'King', rooms: [['203', 1], ['301', 2], ['302', 2]] },
      { name: 'Executive Suite', price: 320000, capacity: 4, bed: 'King', rooms: [['303', 2], ['304', 2]] }
    ]
  },
  {
    type: 'hotel', category: 'hotel', name: 'Zanzibar Palm Beach Hotel', city: 'Zanzibar', neighborhood: 'Nungwi',
    lat: -5.7258, lng: 39.2994, price: 250000, rating: 4.8, reviews: 214,
    image: img('photo-1582719508461-905c673771fd'),
    amenities: ['WiFi', 'Beach access', 'Pool', 'Restaurant', 'Spa', 'Air conditioning'],
    description: 'Beachfront hotel on the northern tip of Zanzibar with ocean-view rooms, a spa and daily breakfast included.',
    floors: ['Ground Floor', 'First Floor'],
    roomTypes: [
      { name: 'Garden View Room', price: 200000, capacity: 2, bed: 'Double', rooms: [['G1', 0], ['G2', 0], ['G3', 0]] },
      { name: 'Ocean View Room', price: 300000, capacity: 3, bed: 'King', rooms: [['O1', 1], ['O2', 1], ['O3', 1]] }
    ]
  },
  {
    type: 'lodge', category: 'lodge', name: 'Ngorongoro Rim Lodge', city: 'Karatu', neighborhood: 'Ngorongoro Rim',
    lat: -3.2467, lng: 35.5833, price: 350000, rating: 4.9, reviews: 96,
    image: img('photo-1520250497591-112f2f40a3f4'),
    amenities: ['WiFi', 'Restaurant', 'Bar', 'Fireplace', 'Game drives', 'Parking'],
    description: 'Safari lodge perched on the crater rim with panoramic views, guided game drives and full-board dining.',
    floors: ['Main Wing'],
    roomTypes: [
      { name: 'Safari Cottage', price: 350000, capacity: 2, bed: 'King', rooms: [['C1', 0], ['C2', 0], ['C3', 0], ['C4', 0]] },
      { name: 'Family Cottage', price: 480000, capacity: 4, bed: 'Twin + Double', rooms: [['F1', 0], ['F2', 0]] }
    ]
  },
  {
    type: 'lodge', category: 'lodge', name: 'Mikumi Bush Lodge', city: 'Morogoro', neighborhood: 'Mikumi',
    lat: -7.3833, lng: 37.0167, price: 150000, rating: 4.3, reviews: 54,
    image: img('photo-1542314831-068cd1dbfeeb'),
    amenities: ['WiFi', 'Restaurant', 'Game drives', 'Parking', 'Garden'],
    description: 'Affordable lodge at the entrance of Mikumi National Park with bandas, a restaurant and guided safaris.',
    floors: ['Main Wing'],
    roomTypes: [
      { name: 'Banda', price: 150000, capacity: 2, bed: 'Double', rooms: [['B1', 0], ['B2', 0], ['B3', 0]] },
      { name: 'Family Banda', price: 220000, capacity: 4, bed: 'Twin + Double', rooms: [['B4', 0], ['B5', 0]] }
    ]
  },
  {
    type: 'motel', category: 'hotel', name: 'Kilimanjaro Road Motel', city: 'Moshi', neighborhood: 'Kiboriloni',
    lat: -3.3500, lng: 37.3333, price: 60000, rating: 4.0, reviews: 41,
    image: img('photo-1551882547-ff40c63fe5fa'),
    amenities: ['WiFi', 'Parking', 'TV', 'Hot water', 'Security'],
    description: 'Clean, budget-friendly roadside motel with secure parking and private rooms, ideal for overnight stops.',
    floors: ['Ground Floor', 'First Floor'],
    roomTypes: [
      { name: 'Single Room', price: 45000, capacity: 1, bed: 'Single', rooms: [['1', 0], ['2', 0], ['3', 0]] },
      { name: 'Double Room', price: 70000, capacity: 2, bed: 'Double', rooms: [['4', 1], ['5', 1], ['6', 1]] }
    ]
  },
  {
    type: 'motel', category: 'hotel', name: 'Highway Rest Motel', city: 'Dodoma', neighborhood: 'Nzuguni',
    lat: -6.1630, lng: 35.7516, price: 50000, rating: 3.9, reviews: 33,
    image: img('photo-1455587734955-081b22074882'),
    amenities: ['WiFi', 'Parking', 'TV', 'Hot water', '24h reception'],
    description: 'Convenient motel along the Dodoma highway with drive-up rooms, free parking and 24-hour reception.',
    floors: ['Ground Floor'],
    roomTypes: [
      { name: 'Standard Room', price: 50000, capacity: 2, bed: 'Double', rooms: [['A1', 0], ['A2', 0], ['A3', 0], ['A4', 0]] },
      { name: 'Twin Room', price: 60000, capacity: 2, bed: 'Twin', rooms: [['A5', 0], ['A6', 0]] }
    ]
  }
];

(async () => {
  await syncDatabase();
  const agent = await User.findOne({ where: { email: 'stay.agent@havenlink.co.tz' } });
  if (!agent) throw new Error('Stay agent not found. Run "npm run seed" first.');

  for (const s of stays) {
    let property = await Property.findOne({ where: { name: s.name, agentId: agent.id } });
    if (property) {
      console.log(`exists   ${s.type.padEnd(6)} ${s.name}`);
      continue;
    }

    const roomCount = s.roomTypes.reduce((n, t) => n + t.rooms.length, 0);
    property = await Property.create({
      name: s.name,
      city: s.city,
      neighborhood: s.neighborhood,
      latitude: s.lat,
      longitude: s.lng,
      formattedAddress: `${s.neighborhood}, ${s.city}, Tanzania`,
      locationVerification: 'verified',
      locationVisibility: 'approximate',
      priceTzs: s.price,
      businessModel: 'bookable',
      category: s.category,
      accommodationType: s.type,
      imageUrl: s.image,
      imageUrls: [s.image],
      rating: s.rating,
      reviewCount: s.reviews,
      bedrooms: roomCount,
      bathrooms: roomCount,
      amenities: s.amenities,
      description: s.description,
      available: true,
      furnished: true,
      parking: s.amenities.includes('Parking'),
      water: true,
      electricity: true,
      security: true,
      propertyVerification: 'verified',
      ownerVerification: 'verified',
      managerName: agent.fullName,
      listingStatus: 'published',
      rentalPeriod: 'day',
      agentId: agent.id
    });

    const floors = [];
    for (const [i, label] of s.floors.entries()) {
      floors.push(await Floor.create({ propertyId: property.id, label, sortOrder: i }));
    }

    for (const t of s.roomTypes) {
      const roomType = await RoomType.create({
        listingId: property.id,
        name: t.name,
        nightlyPriceTzs: t.price,
        capacity: t.capacity,
        totalRooms: t.rooms.length,
        amenities: s.amenities.slice(0, 4),
        imageUrls: [s.image],
        primaryImageUrl: s.image,
        bedType: t.bed,
        numberOfBeds: 1,
        bathroomType: 'Private',
        description: `${t.name} at ${s.name}.`
      });
      for (const [roomNumber, floorIndex] of t.rooms) {
        await Room.create({
          propertyId: property.id,
          floorId: floors[floorIndex].id,
          roomTypeId: roomType.id,
          roomNumber
        });
      }
    }
    console.log(`created  ${s.type.padEnd(6)} ${s.name} (${roomCount} rooms)`);
  }
  await sequelize.close();
})().catch((e) => { console.error(e); process.exit(1); });
