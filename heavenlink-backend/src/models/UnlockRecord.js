const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const UnlockRecord = sequelize.define('UnlockRecord', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
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
    allowNull: false,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  paymentTransactionId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'PaymentTransactions',
      key: 'id'
    }
  },
  status: {
    type: DataTypes.ENUM('awaitingPayment', 'active', 'failed', 'refunded'),
    defaultValue: 'awaitingPayment',
    allowNull: false
  },
  confirmedAt: {
    type: DataTypes.DATE,
    allowNull: true
  },
  amountTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  }
}, {
  timestamps: true,
  indexes: [
    {
      unique: true,
      fields: ['customerId', 'listingId']
    },
    {
      fields: ['paymentTransactionId']
    },
    {
      fields: ['status']
    }
  ]
});

// Instance methods
UnlockRecord.prototype.isActive = function() {
  return this.status === 'active';
};

module.exports = UnlockRecord;
