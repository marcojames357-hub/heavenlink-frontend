const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const Property = sequelize.define('Property', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  name: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [3, 200]
    }
  },
  city: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  neighborhood: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  priceTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  businessModel: {
    type: DataTypes.ENUM('bookable', 'contactUnlock'),
    allowNull: false
  },
  category: {
    type: DataTypes.ENUM('hotel', 'lodge', 'servicedApartment', 'shortStayApartment', 'house', 'room', 'sharedAccommodation'),
    allowNull: false
  },
  imageUrl: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      isUrl: true
    }
  },
  imageUrls: {
    type: DataTypes.JSON,
    defaultValue: [],
    validate: {
      isArrayOfStrings(value) {
        if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
          throw new Error('imageUrls must be an array of strings');
        }
      }
    }
  },
  rating: {
    type: DataTypes.FLOAT,
    defaultValue: 0,
    validate: {
      min: 0,
      max: 5
    }
  },
  reviewCount: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: 0
    }
  },
  bedrooms: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  bathrooms: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  amenities: {
    type: DataTypes.JSON,
    defaultValue: []
  },
  description: {
    type: DataTypes.TEXT,
    allowNull: false,
    validate: {
      len: [10, 5000]
    }
  },
  available: {
    type: DataTypes.BOOLEAN,
    defaultValue: true
  },
  furnished: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  parking: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  water: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  electricity: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  security: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  propertyVerification: {
    type: DataTypes.ENUM('unverified', 'pending', 'verified'),
    defaultValue: 'unverified'
  },
  ownerVerification: {
    type: DataTypes.ENUM('unverified', 'pending', 'verified'),
    defaultValue: 'unverified'
  },
  managerName: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  listingStatus: {
    type: DataTypes.ENUM('draft', 'pendingReview', 'published', 'paused', 'rejected'),
    defaultValue: 'draft'
  },
  agentId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Users',
      key: 'id'
    }
  },
  rentalPeriod: {
    type: DataTypes.STRING,
    defaultValue: 'month',
    validate: {
      isIn: [['day', 'week', 'month', 'year']]
    }
  },
  reportedCount: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: 0
    }
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['agentId']
    },
    {
      fields: ['businessModel']
    },
    {
      fields: ['listingStatus']
    },
    {
      fields: ['city', 'neighborhood']
    }
  ]
});

// Instance methods
Property.prototype.isPublic = function() {
  return this.listingStatus === 'published';
};

Property.prototype.hasValidBusinessModel = function() {
  const bookableCategories = ['hotel', 'lodge', 'servicedApartment', 'shortStayApartment'];
  const rentalCategories = ['house', 'room', 'sharedAccommodation'];

  if (this.businessModel === 'bookable') {
    return bookableCategories.includes(this.category);
  } else {
    return rentalCategories.includes(this.category);
  }
};

module.exports = Property;
