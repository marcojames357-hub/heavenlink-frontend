const { AgentWorkspace, Property } = require('../models');

const WORKSPACES = ['RENTAL', 'APARTMENT', 'HOTEL'];
const WORKSPACE_CAPABILITY = {
  RENTAL: 'rentalProperty',
  APARTMENT: 'accommodationBooking',
  HOTEL: 'accommodationBooking'
};
const CATEGORY_WORKSPACE = {
  house: 'RENTAL', room: 'RENTAL', sharedAccommodation: 'RENTAL',
  servicedApartment: 'APARTMENT', shortStayApartment: 'APARTMENT',
  hotel: 'HOTEL', lodge: 'HOTEL'
};

const workspaceForProperty = (property) => {
  if (property.businessModel === 'contactUnlock') return 'RENTAL';
  if (['hotel', 'motel', 'lodge'].includes(property.accommodationType)) return 'HOTEL';
  return CATEGORY_WORKSPACE[property.category] || null;
};

async function grantWorkspace(user, workspace, source = 'registration', status = 'active') {
  if (!WORKSPACES.includes(workspace)) throw new Error('Unknown workspace');
  const [record] = await AgentWorkspace.findOrCreate({
    where: { userId: user.id, workspace }, defaults: { status, source }
  });
  if (record.status !== status && status === 'active' && record.status !== 'revoked') {
    await record.update({ status });
  }
  const capability = WORKSPACE_CAPABILITY[workspace];
  const capabilities = user.capabilities || [];
  if (status === 'active' && !capabilities.includes(capability)) {
    await user.update({ capabilities: [...capabilities, capability] });
  }
  return record;
}

// Existing agents are migrated from the properties they already manage. Agents whose
// classification cannot be derived are placed in pending_review instead of guessed.
async function ensureAgentWorkspaces(user) {
  if (!['RENTAL_AGENT', 'STAY_AGENT'].includes(user.role)) return [];
  let records = await AgentWorkspace.findAll({ where: { userId: user.id } });
  if (records.length) return records;
  if (user.role === 'RENTAL_AGENT') {
    await grantWorkspace(user, 'RENTAL', 'legacyMigration');
  } else {
    const properties = await Property.findAll({
      where: { agentId: user.id }, attributes: ['category', 'accommodationType', 'businessModel']
    });
    const derived = new Set(properties.map(workspaceForProperty).filter(Boolean));
    if (derived.size === 0) {
      await AgentWorkspace.bulkCreate(['APARTMENT', 'HOTEL'].map((workspace) => ({
        userId: user.id, workspace, status: 'pending_review', source: 'legacyMigration'
      })));
    } else {
      for (const workspace of derived) await grantWorkspace(user, workspace, 'legacyMigration');
    }
  }
  records = await AgentWorkspace.findAll({ where: { userId: user.id } });
  return records;
}

async function hasWorkspace(user, workspace) {
  if (user.role === 'ADMIN') return true;
  const records = await ensureAgentWorkspaces(user);
  return records.some((record) => record.workspace === workspace && record.status === 'active');
}

module.exports = {
  WORKSPACES, WORKSPACE_CAPABILITY, workspaceForProperty,
  grantWorkspace, ensureAgentWorkspaces, hasWorkspace
};
