const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

// Explicit, server-side record of which management workspaces an agent may use.
const AgentWorkspace = sequelize.define('AgentWorkspace', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  userId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  workspace: { type: DataTypes.STRING(20), allowNull: false },
  status: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'active' },
  source: { type: DataTypes.STRING(30), allowNull: false, defaultValue: 'registration' }
}, {
  indexes: [{ fields: ['userId', 'workspace'], unique: true }]
});

module.exports = AgentWorkspace;
