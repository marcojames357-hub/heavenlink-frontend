const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const OtpChallenge = sequelize.define('OtpChallenge', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  phoneE164: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      is: /^\+255\d{9}$/
    }
  },
  sessionId: {
    type: DataTypes.STRING,
    allowNull: false
  },
  codeHash: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  expiresAt: {
    type: DataTypes.DATE,
    allowNull: false
  },
  resendAvailableAt: {
    type: DataTypes.DATE,
    allowNull: false
  },
  attempts: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: 0
    }
  },
  resends: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: 0
    }
  },
  verified: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  consumedAt: {
    type: DataTypes.DATE,
    allowNull: true
  },
  provider: {
    type: DataTypes.STRING,
    defaultValue: 'none'
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['phoneE164']
    },
    {
      fields: ['sessionId']
    },
    {
      fields: ['expiresAt']
    }
  ]
});

// Instance methods
OtpChallenge.prototype.isExpired = function() {
  return new Date() > this.expiresAt;
};

OtpChallenge.prototype.canResend = function() {
  return new Date() > this.resendAvailableAt;
};

OtpChallenge.prototype.hasAttemptsLeft = function(maxAttempts = 5) {
  return this.attempts < maxAttempts;
};

OtpChallenge.prototype.hasResendsLeft = function(maxResends = 5) {
  return this.resends < maxResends;
};

module.exports = OtpChallenge;
