const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const NotificationPreference = sequelize.define('NotificationPreference', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  userId: {
    type: DataTypes.UUID, allowNull: false, unique: true,
    references: { model: 'Users', key: 'id' }
  },
  sms: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true },
  email: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true },
  mutedCategories: { type: DataTypes.JSON, allowNull: false, defaultValue: [] }
});

module.exports = NotificationPreference;
