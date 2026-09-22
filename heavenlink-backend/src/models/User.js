const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');
const bcrypt = require('bcryptjs');

const User = sequelize.define('User', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  fullName: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  email: {
    type: DataTypes.STRING,
    allowNull: false,
    unique: true,
    validate: {
      isEmail: true
    }
  },
  phone: {
    type: DataTypes.STRING,
    allowNull: false,
    unique: true,
    validate: {
      is: /^\+255\d{9}$/ // E.164 format for Tanzania
    }
  },
  password: {
    type: DataTypes.STRING,
    allowNull: true,
    validate: {
      len: [4, 255]
    }
  },
  role: {
    type: DataTypes.ENUM('CUSTOMER', 'RENTAL_AGENT', 'STAY_AGENT', 'ADMIN'),
    defaultValue: 'CUSTOMER',
    allowNull: false
  },
  verification: {
    type: DataTypes.ENUM('unverified', 'pending', 'verified'),
    defaultValue: 'unverified',
    allowNull: false
  },
  accountEnabled: {
    type: DataTypes.BOOLEAN,
    defaultValue: true,
    allowNull: false
  },
  capabilities: {
    type: DataTypes.JSON,
    defaultValue: []
  }
}, {
  timestamps: true,
  hooks: {
    beforeCreate: async (user) => {
      if (user.password) {
        user.password = await bcrypt.hash(user.password, 10);
      }
    },
    beforeUpdate: async (user) => {
      if (user.changed('password')) {
        user.password = await bcrypt.hash(user.password, 10);
      }
    }
  }
});

// Instance methods
User.prototype.comparePassword = async function(candidatePassword) {
  if (!this.password) return false;
  return bcrypt.compare(candidatePassword, this.password);
};

User.prototype.hasCapability = function(capability) {
  if (this.role === 'ADMIN') return true;
  if (this.role === 'RENTAL_AGENT' && capability === 'rentalProperty') return true;
  if (this.role === 'STAY_AGENT' && capability === 'accommodationBooking') return true;
  return this.capabilities.includes(capability);
};

User.prototype.canPublish = function() {
  return this.accountEnabled && this.verification === 'verified';
};

module.exports = User;
