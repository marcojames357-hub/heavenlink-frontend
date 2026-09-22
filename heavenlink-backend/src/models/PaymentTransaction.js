const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const PaymentTransaction = sequelize.define('PaymentTransaction', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  reference: {
    type: DataTypes.STRING,
    allowNull: false,
    unique: true
  },
  idempotencyKey: {
    type: DataTypes.STRING,
    allowNull: true
  },
  purpose: {
    type: DataTypes.ENUM('rentalContactUnlock', 'accommodationBooking'),
    allowNull: false
  },
  amountTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  currency: {
    type: DataTypes.STRING,
    defaultValue: 'TZS',
    allowNull: false
  },
  methodId: {
    type: DataTypes.STRING,
    allowNull: false
  },
  customerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Users',
      key: 'id'
    }
  },
  listingId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  bookingId: {
    type: DataTypes.UUID,
    allowNull: true
  },
  status: {
    type: DataTypes.ENUM('pending', 'succeeded', 'failed', 'cancelled', 'expired', 'refunded'),
    defaultValue: 'pending',
    allowNull: false
  },
  verifiedAt: {
    type: DataTypes.DATE,
    allowNull: true
  },
  failureMessage: {
    type: DataTypes.TEXT,
    allowNull: true
  },
  providerResponse: {
    type: DataTypes.JSON,
    defaultValue: {}
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['customerId']
    },
    {
      fields: ['status']
    },
    {
      fields: ['purpose']
    },
    {
      fields: ['reference'],
      unique: true
    },
    {
      fields: ['idempotencyKey'],
      unique: true
    }
  ]
});

// Instance methods
PaymentTransaction.prototype.isVerified = function() {
  return this.status === 'succeeded';
};

module.exports = PaymentTransaction;
