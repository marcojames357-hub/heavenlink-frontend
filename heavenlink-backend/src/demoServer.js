'use strict';
// Uses only the isolated demo dataset, never the application's original DB.
const crypto = require('crypto');
const { validateRuntimeTarget } = require('./seedDemo');
(async () => {
  const target = await validateRuntimeTarget();
  process.env.SQLITE_STORAGE = target.database;
  process.env.PORT = process.env.HAVEN_DEMO_API_PORT || '3001';
  process.env.HOST = '127.0.0.1';
  process.env.NODE_ENV = 'development';
  process.env.HAVEN_DEMO_MODE = 'true';
  process.env.SMS_PROVIDER = 'none';
  process.env.JWT_SECRET = crypto.randomBytes(48).toString('hex');
  process.env.OTP_SECRET = crypto.randomBytes(48).toString('hex');
  await require('./server').startServer();
  console.log('LOCAL DEMO: isolated havenlink-demo.sqlite; sample accounts only; SMS and real payments are not enabled.');
})().catch(error => { console.error('Demo API startup failed:', error.message); process.exitCode = 1; });
