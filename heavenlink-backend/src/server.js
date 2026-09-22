require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./routes/auth');
const otpRoutes = require('./routes/otp');
const propertyRoutes = require('./routes/properties');
const paymentRoutes = require('./routes/payments');
const agentRoutes = require('./routes/agents');
const adminRoutes = require('./routes/admin');
const bookingRoutes = require('./routes/bookings');
const { errorHandler } = require('./middleware/errorHandler');
const { syncDatabase } = require('./models');

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.NODE_ENV === 'production'
    ? ['https://heavenlink.co.tz']
    : ['http://localhost:8080', 'http://localhost:3000'],
  credentials: true
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// OTP rate limiting (stricter)
const otpLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5, // limit each IP to 5 OTP requests per minute
  message: 'Too many OTP requests, please try again later.'
});
app.use('/api/v1/otp/', otpLimiter);

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// API Routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/otp', otpRoutes);
app.use('/api/v1/properties', propertyRoutes);
app.use('/api/v1/payments', paymentRoutes);
app.use('/api/v1/agents', agentRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/bookings', bookingRoutes);

// Error handling
app.use(errorHandler);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

const startServer = async () => {
  await syncDatabase();
  return app.listen(PORT, () => {
    console.log(`Haven Link Backend Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV}`);
  });
};

if (require.main === module) {
  startServer().catch((error) => {
    console.error('Failed to start Haven Link API:', error);
    process.exitCode = 1;
  });
}

module.exports = { app, startServer };
