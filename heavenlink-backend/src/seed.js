require('dotenv').config();
const { User, AgentWorkspace, syncDatabase } = require('./models');
const sequelize = require('./config/database');

const accounts = [
  { fullName: 'Haven Admin', email: 'admin@havenlink.co.tz', phone: '+255700000001', password: 'Admin@12345', role: 'ADMIN', capabilities: [] },
  { fullName: 'Rental Agent', email: 'rental.agent@havenlink.co.tz', phone: '+255700000002', password: 'Rental@12345', role: 'RENTAL_AGENT', capabilities: ['rentalProperty'] },
  { fullName: 'Stay Agent', email: 'stay.agent@havenlink.co.tz', phone: '+255700000003', password: 'Stay@12345', role: 'STAY_AGENT', capabilities: ['accommodationBooking'], workspaces: ['HOTEL'] },
  { fullName: 'Demo Customer', email: 'customer@havenlink.co.tz', phone: '+255700000004', password: 'Customer@12345', role: 'CUSTOMER', capabilities: [] },
  { fullName: 'Apartment Agent', email: 'apartment.agent@havenlink.co.tz', phone: '+255700000005', password: 'Apartment@12345', role: 'STAY_AGENT', capabilities: ['accommodationBooking'], workspaces: ['APARTMENT'] }
];

(async () => {
  await syncDatabase();
  for (const { workspaces = [], ...a } of accounts) {
    const existing = await User.findOne({ where: { email: a.email } });
    const user = existing
      ? await existing.update({ ...a, verification: 'verified', accountEnabled: true })
      : await User.create({ ...a, verification: 'verified', accountEnabled: true });
    for (const workspace of workspaces) {
      await AgentWorkspace.findOrCreate({
        where: { userId: user.id, workspace },
        defaults: { status: 'active', source: 'registration' }
      });
    }
    console.log(`${a.role.padEnd(13)} ${a.email}  ${a.password}`);
  }
  await sequelize.close();
})().catch((e) => { console.error(e); process.exit(1); });
