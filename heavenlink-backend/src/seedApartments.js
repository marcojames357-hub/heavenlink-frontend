require('dotenv').config();
const { User, Property, syncDatabase } = require('./models');
const sequelize = require('./config/database');

const img = (id) => `https://images.unsplash.com/${id}?auto=format&fit=crop&w=1200&q=80`;

const apartments = [
  {
    category: 'shortStayApartment', name: 'Masaki Sea View Apartment', city: 'Dar es Salaam', neighborhood: 'Masaki',
    region: 'Dar es Salaam', lat: -6.7456, lng: 39.2810, price: 220000, weekend: 260000, cleaning: 30000,
    bedrooms: 2, bathrooms: 2, beds: 3, guests: 4, rating: 4.8, reviews: 36,
    images: [
      ['photo-1502672260266-1c1ef2d93688', 'Cover'], ['photo-1493809842364-78817add7ffb', 'Living room'],
      ['photo-1505691938895-1758d7feb511', 'Bedroom'], ['photo-1552321554-5fefe8c9ef14', 'Bathroom']
    ],
    amenities: ['WiFi', 'Air conditioning', 'Kitchen', 'Parking', 'Ocean view', 'Security', 'Washing machine'],
    description: 'Bright two-bedroom apartment with a balcony over the Indian Ocean, fully equipped kitchen and secure parking. Walk to restaurants and the Msasani peninsula.',
    rules: { minNights: 2, maxNights: 30, checkInTime: '14:00', checkOutTime: '11:00',
      cancellationPolicy: 'Free cancellation up to 48 hours before check-in. After that the first night is charged.',
      houseRules: 'No smoking indoors. No parties or events. Quiet hours from 22:00 to 07:00.' }
  },
  {
    category: 'servicedApartment', name: 'Arusha Garden Residence', city: 'Arusha', neighborhood: 'Njiro',
    region: 'Arusha', lat: -3.3869, lng: 36.6830, price: 180000, weekend: 180000, cleaning: 25000,
    bedrooms: 3, bathrooms: 2, beds: 5, guests: 6, rating: 4.6, reviews: 21,
    images: [
      ['photo-1522708323590-d24dbb6b0267', 'Cover'], ['photo-1484154218962-a197022b5858', 'Kitchen'],
      ['photo-1540518614846-7eded433c457', 'Bedroom'], ['photo-1560448204-e02f11c3d0e2', 'Living room']
    ],
    amenities: ['WiFi', 'Kitchen', 'Garden', 'Parking', 'Security', 'Hot water', 'Television'],
    description: 'Three-bedroom serviced apartment in a quiet garden compound, ideal for families and small groups. Booked as one whole unit with daily housekeeping on request.',
    rules: { minNights: 1, maxNights: 60, checkInTime: '13:00', checkOutTime: '10:00',
      cancellationPolicy: 'Free cancellation up to 7 days before check-in.',
      houseRules: 'Pets are not allowed. Visitors must leave by 21:00.' }
  },
  {
    category: 'shortStayApartment', name: 'Stone Town Heritage Apartment', city: 'Zanzibar', neighborhood: 'Stone Town',
    region: 'Zanzibar Urban/West', lat: -6.1659, lng: 39.1925, price: 150000, weekend: 190000, cleaning: 20000,
    bedrooms: 1, bathrooms: 1, beds: 1, guests: 2, rating: 4.9, reviews: 58,
    images: [
      ['photo-1536376072261-38c75010e6c9', 'Cover'], ['photo-1519710164239-da123dc03ef4', 'Living room'],
      ['photo-1522771739844-6a9f6d5f14af', 'Bedroom']
    ],
    amenities: ['WiFi', 'Air conditioning', 'Kitchen', 'Rooftop terrace', 'Hot water'],
    description: 'Romantic one-bedroom apartment in a restored Swahili house with carved doors and a shared rooftop terrace, steps from Forodhani Gardens.',
    rules: { minNights: 2, maxNights: 14, checkInTime: '15:00', checkOutTime: '11:00',
      cancellationPolicy: 'Free cancellation up to 72 hours before check-in.',
      houseRules: 'No smoking. Respect neighbours; quiet after 22:00.' }
  }
];

(async () => {
  await syncDatabase();
  const agent = await User.findOne({ where: { email: 'apartment.agent@havenlink.co.tz' } });
  if (!agent) throw new Error('Apartment agent not found. Run "npm run seed" first.');

  for (const a of apartments) {
    if (await Property.findOne({ where: { name: a.name, agentId: agent.id } })) {
      console.log(`exists   ${a.name}`);
      continue;
    }
    const urls = a.images.map(([id]) => img(id));
    await Property.create({
      name: a.name,
      city: a.city,
      neighborhood: a.neighborhood,
      latitude: a.lat,
      longitude: a.lng,
      priceTzs: a.price,
      businessModel: 'bookable',
      category: a.category,
      imageUrl: urls[0],
      imageUrls: urls,
      rating: a.rating,
      reviewCount: a.reviews,
      bedrooms: a.bedrooms,
      bathrooms: a.bathrooms,
      maxGuests: a.guests,
      stayRules: {
        ...a.rules,
        weekendPriceTzs: a.weekend,
        cleaningFeeTzs: a.cleaning,
        beds: a.beds,
        country: 'Tanzania',
        region: a.region,
        photoLabels: Object.fromEntries(a.images.map(([, label], i) => [urls[i], label]))
      },
      amenities: a.amenities,
      description: a.description,
      available: true,
      furnished: true,
      parking: a.amenities.includes('Parking'),
      water: true,
      electricity: true,
      security: a.amenities.includes('Security'),
      propertyVerification: 'verified',
      ownerVerification: 'verified',
      managerName: agent.fullName,
      listingStatus: 'published',
      rentalPeriod: 'day',
      agentId: agent.id
    });
    console.log(`created  ${a.category.padEnd(19)} ${a.name}`);
  }
  await sequelize.close();
})().catch((e) => { console.error(e); process.exit(1); });
