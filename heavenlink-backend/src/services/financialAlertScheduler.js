const { Property, User } = require('../models');
const { refreshPropertyAlerts } = require('./financialManagement');

let running = false;

async function refreshFinancialAlerts() {
  if (running) return;
  running = true;
  try {
    let offset = 0;
    const batchSize = 100;
    while (true) {
      const properties = await Property.findAll({
        where: { businessModel: ['contactUnlock', 'bookable'] },
        attributes: ['id', 'name', 'businessModel', 'agentId'],
        order: [['id', 'ASC']],
        limit: batchSize,
        offset
      });
      if (!properties.length) break;
      const owners = await User.findAll({
        where: { id: properties.map((property) => property.agentId) },
        attributes: ['id']
      });
      const ownerIds = new Set(owners.map((owner) => owner.id));
      for (const property of properties) {
        if (ownerIds.has(property.agentId)) {
          await refreshPropertyAlerts(property, property.agentId);
        }
      }
      if (properties.length < batchSize) break;
      offset += batchSize;
    }
  } finally {
    running = false;
  }
}

function startFinancialAlertScheduler() {
  const run = () => refreshFinancialAlerts().catch((error) => {
    console.error('Refresh financial alerts failed:', error);
  });
  run();
  const timer = setInterval(run, 60 * 60 * 1000);
  timer.unref();
  return timer;
}

module.exports = { refreshFinancialAlerts, startFinancialAlertScheduler };
