const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const GuestMessage = sequelize.define('GuestMessage', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  bookingId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Bookings',
      key: 'id'
    }
  },
  senderId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Users',
      key: 'id'
    }
  },
  senderType: {
    type: DataTypes.ENUM('guest', 'agent'),
    allowNull: false
  },
  body: {
    type: DataTypes.TEXT,
    allowNull: false,
    validate: {
      len: [1, 2000]
    }
  },
  readAt: {
    type: DataTypes.DATE,
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['bookingId']
    },
    {
      fields: ['senderId']
    },
    {
      fields: ['createdAt']
    }
  ]
});

// Instance methods
GuestMessage.prototype.isRead = function() {
  return this.readAt !== null;
};

module.exports = GuestMessage;
