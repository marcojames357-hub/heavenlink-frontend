const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const ReviewReport = sequelize.define('ReviewReport', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  reviewId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Reviews', key: 'id' }
  },
  reporterId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  reason: {
    type: DataTypes.STRING(1000),
    allowNull: false,
    validate: { len: [5, 1000] }
  },
  status: {
    type: DataTypes.ENUM('pending', 'resolved', 'dismissed'),
    allowNull: false,
    defaultValue: 'pending'
  }
}, {
  timestamps: true,
  indexes: [
    { unique: true, fields: ['reviewId', 'reporterId'] },
    { fields: ['status', 'createdAt'] }
  ]
});

module.exports = ReviewReport;