const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const Booking = sequelize.define('Booking', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  requestKey: {
    type: DataTypes.STRING,
    allowNull: true
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  customerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Users',
      key: 'id'
    }
  },
  checkIn: {
    type: DataTypes.DATE,
    allowNull: false
  },
  checkOut: {
    type: DataTypes.DATE,
    allowNull: false
  },
  guestName: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  guestPhone: {
    type: DataTypes.STRING,
    allowNull: true,
    validate: {
      is: /^\+255\d{9}$/
    }
  },
  guestCount: {
    type: DataTypes.INTEGER,
    defaultValue: 1,
    validate: {
      min: 1,
      max: 20
    }
  },
  subtotalTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  feeTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  totalTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  status: {
    type: DataTypes.ENUM('pending', 'confirmed', 'completed', 'cancelled'),
    defaultValue: 'pending',
    allowNull: false
  },
  paymentTransactionId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: {
      model: 'PaymentTransactions',
      key: 'id'
    }
  },
  roomTypeId: {
    type: DataTypes.UUID,
    allowNull: true
  },
  assignedRoomId: {
    type: DataTypes.UUID,
    allowNull: true
  },
  holdExpiresAt: {
    type: DataTypes.DATE,
    allowNull: true
  },
  checkedOutAt: {
    type: DataTypes.DATE,
    allowNull: true
  },
  specialRequests: {
    type: DataTypes.TEXT,
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['customerId']
    },
    {
      fields: ['propertyId']
    },
    {
      fields: ['status']
    },
    {
      fields: ['checkIn', 'checkOut']
    },
    {
      fields: ['requestKey'],
      unique: true
    }
  ]
});

// Instance methods
Booking.prototype.isActive = function() {
  return ['pending', 'confirmed'].includes(this.status);
};

Booking.prototype.calculateNights = function() {
  const checkInDate = new Date(this.checkIn);
  const checkOutDate = new Date(this.checkOut);
  const diffTime = Math.abs(checkOutDate - checkInDate);
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  return diffDays;
};

module.exports = Booking;
