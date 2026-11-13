const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

// visibility: internal = admin only, customer = customer + admin,
// agent = agent + admin (only for reports shared with the agent).
const ProblemReportNote = sequelize.define('ProblemReportNote', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  reportId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'ProblemReports', key: 'id' }
  },
  authorId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  authorRole: { type: DataTypes.STRING(20), allowNull: false },
  visibility: {
    type: DataTypes.ENUM('internal', 'customer', 'agent'),
    allowNull: false
  },
  kind: {
    type: DataTypes.ENUM('note', 'reply', 'resolution'),
    allowNull: false,
    defaultValue: 'note'
  },
  body: { type: DataTypes.STRING(2000), allowNull: false }
}, {
  timestamps: true,
  indexes: [{ fields: ['reportId', 'createdAt'] }]
});

module.exports = ProblemReportNote;
