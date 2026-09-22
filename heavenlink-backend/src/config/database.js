const { Sequelize } = require('sequelize');
const fs = require('fs');
const path = require('path');

const storage = path.resolve(
  process.env.SQLITE_STORAGE || path.join(__dirname, '../../data/havenlink.sqlite')
);
fs.mkdirSync(path.dirname(storage), { recursive: true });

const sequelize = new Sequelize({
  dialect: 'sqlite',
  storage,
  logging: process.env.NODE_ENV === 'development' ? console.log : false,
  retry: { max: 3 }
});

module.exports = sequelize;
