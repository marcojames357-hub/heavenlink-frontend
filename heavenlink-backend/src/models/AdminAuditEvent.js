const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const AdminAuditEvent = sequelize.define('AdminAuditEvent', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  actorId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  action: {
    type: DataTypes.STRING(80),
    allowNull: false
  },
  entityType: {
    type: DataTypes.STRING(80),
    allowNull: false
  },
  entityId: {
    type: DataTypes.STRING(80),
    allowNull: false
  },
  metadata: {
    type: DataTypes.JSON,
    allowNull: false,
    defaultValue: {}
  },
  ipAddress: {
    type: DataTypes.STRING(64),
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    { fields: ['actorId'] },
    { fields: ['entityType', 'entityId'] },
    { fields: ['createdAt'] }
  ]
});

module.exports = AdminAuditEvent;