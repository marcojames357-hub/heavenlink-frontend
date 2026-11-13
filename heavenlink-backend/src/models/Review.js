const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const ratingFields = [
  'cleanliness',
  'accuracy',
  'checkIn',
  'communication',
  'location',
  'value',
  'comfort',
  'amenities'
];

const Review = sequelize.define('Review', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  bookingId: {
    type: DataTypes.UUID,
    allowNull: false,
    unique: true,
    references: { model: 'Bookings', key: 'id' }
  },
  reviewerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  cleanliness: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  accuracy: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  checkIn: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  communication: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  location: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  value: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 1, max: 5 } },
  comfort: { type: DataTypes.INTEGER, allowNull: true, validate: { min: 1, max: 5 } },
  amenities: { type: DataTypes.INTEGER, allowNull: true, validate: { min: 1, max: 5 } },
  overallRating: {
    type: DataTypes.FLOAT,
    allowNull: false,
    validate: { min: 1, max: 5 }
  },
  images: { type: DataTypes.JSON, allowNull: false, defaultValue: [] },
  agentResponse: { type: DataTypes.STRING(1500), allowNull: true },
  agentResponseAt: { type: DataTypes.DATE, allowNull: true },
  agentResponderId: { type: DataTypes.UUID, allowNull: true },
  publishedAt: { type: DataTypes.DATE, allowNull: true },
  title: { type: DataTypes.STRING(120), allowNull: true },
  comment: { type: DataTypes.TEXT, allowNull: true },
  status: {
    type: DataTypes.ENUM('published', 'hidden', 'rejected'),
    allowNull: false,
    defaultValue: 'published'
  },
  moderationReason: { type: DataTypes.STRING(1000), allowNull: true }
}, {
  timestamps: true,
  indexes: [
    { unique: true, fields: ['bookingId'] },
    { fields: ['propertyId', 'status', 'createdAt'] },
    { fields: ['reviewerId', 'createdAt'] }
  ]
});

Review.ratingFields = ratingFields;

module.exports = Review;