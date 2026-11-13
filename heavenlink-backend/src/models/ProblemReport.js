const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const categories = [
  'maintenance',
  'cleanliness',
  'utilities',
  'safety',
  'charges',
  'misleading_info',
  'staff_behavior',
  'other'
];

// Categories that are routed to Admin first and hidden from the agent.
const sensitiveCategories = ['safety', 'staff_behavior'];

const statuses = [
  'open',
  'under_review',
  'awaiting_agent',
  'awaiting_customer',
  'resolved',
  'closed'
];

const ProblemReport = sequelize.define('ProblemReport', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  reference: { type: DataTypes.STRING(24), allowNull: false, unique: true },
  bookingId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Bookings', key: 'id' }
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  customerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  assignedAgentId: { type: DataTypes.UUID, allowNull: true },
  assignedStaffId: { type: DataTypes.UUID, allowNull: true },
  category: { type: DataTypes.ENUM(...categories), allowNull: false },
  severity: {
    type: DataTypes.ENUM('general', 'urgent'),
    allowNull: false,
    defaultValue: 'general'
  },
  description: { type: DataTypes.TEXT, allowNull: false },
  evidenceFiles: { type: DataTypes.JSON, allowNull: false, defaultValue: [] },
  visibilityClassification: {
    type: DataTypes.ENUM('ordinary', 'sensitive'),
    allowNull: false,
    defaultValue: 'ordinary'
  },
  // Admin decides when a sensitive report may be shared with the agent.
  sharedWithAgent: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
  status: {
    type: DataTypes.ENUM(...statuses),
    allowNull: false,
    defaultValue: 'open'
  },
  resolvedAt: { type: DataTypes.DATE, allowNull: true }
}, {
  timestamps: true,
  indexes: [
    { fields: ['customerId', 'createdAt'] },
    { fields: ['assignedAgentId', 'visibilityClassification', 'status'] },
    { fields: ['propertyId'] },
    { fields: ['status', 'severity'] }
  ]
});

ProblemReport.categories = categories;
ProblemReport.sensitiveCategories = sensitiveCategories;
ProblemReport.statuses = statuses;

module.exports = ProblemReport;
