const express = require('express');
const crypto = require('crypto');
const { body, validationResult } = require('express-validator');
const { OtpChallenge } = require('../models');
const smsService = require('../services/smsService');

const router = express.Router();
const CODE_EXPIRY_SECONDS = Number.parseInt(process.env.OTP_CODE_TTL, 10) || 300;
const RESEND_COOLDOWN_SECONDS = Number.parseInt(process.env.OTP_RESEND_COOLDOWN, 10) || 45;
const MAX_ATTEMPTS = Number.parseInt(process.env.OTP_MAX_ATTEMPTS, 10) || 5;
const MAX_RESENDS = Number.parseInt(process.env.OTP_MAX_RESENDS, 10) || 5;
const CODE_SECRET = process.env.OTP_SECRET || process.env.JWT_SECRET;

const generateCode = () => crypto.randomInt(100000, 1000000).toString();
const hashCode = (code) => crypto.createHmac('sha256', CODE_SECRET).update(code).digest('hex');

const validationErrors = (req, res) => {
  const errors = validationResult(req);
  if (errors.isEmpty()) return false;
  res.status(400).json({ error: 'Validation failed', details: errors.array() });
  return true;
};

const challengeResponse = (res, challenge, status = 200) => {
  const now = new Date();
  const secondsUntilResend = Math.max(
    0,
    Math.ceil((challenge.resendAvailableAt - now) / 1000)
  );
  return res.status(status).json({
    challengeId: challenge.id,
    phone: challenge.phoneE164,
    phoneE164: challenge.phoneE164,
    sessionId: challenge.sessionId,
    issuedAt: challenge.updatedAt.toISOString(),
    expiresAt: challenge.expiresAt.toISOString(),
    ttlSeconds: CODE_EXPIRY_SECONDS,
    resendAfterSeconds: secondsUntilResend,
    resendAvailableAt: challenge.resendAvailableAt.toISOString(),
    attemptsRemaining: Math.max(0, MAX_ATTEMPTS - challenge.attempts),
    resendCount: challenge.resends,
    provider: smsService.getProviderLabel()
  });
};

const validateProvider = (res) => {
  if (CODE_SECRET && smsService.isConfigured()) return true;
  res.status(503).json({
    error: 'SMS service not configured',
    message: 'SMS verification is not available. Please contact support.'
  });
  return false;
};

router.post('/request', [
  body('phoneE164').matches(/^\+255\d{9}$/),
  body('sessionId').isString().trim().isLength({ min: 1, max: 128 })
], async (req, res) => {
  if (validationErrors(req, res)) return;
  if (!validateProvider(res)) return;

  const { phoneE164, sessionId } = req.body;
  const now = new Date();
  let challenge;
  let isNew = false;

  try {
    challenge = await OtpChallenge.findOne({
      where: { phoneE164, sessionId, verified: false, consumedAt: null },
      order: [['createdAt', 'DESC']]
    });

    if (challenge && !challenge.canResend()) {
      const retryAfter = Math.ceil((challenge.resendAvailableAt - now) / 1000);
      return res.status(429).json({ error: 'Too many requests', retryAfter });
    }
    if (challenge && !challenge.hasResendsLeft(MAX_RESENDS)) {
      return res.status(429).json({ error: 'Resend limit exceeded' });
    }

    const code = generateCode();
    const expiresAt = new Date(now.getTime() + CODE_EXPIRY_SECONDS * 1000);
    const resendAvailableAt = new Date(now.getTime() + RESEND_COOLDOWN_SECONDS * 1000);
    if (challenge) {
      await challenge.update({
        codeHash: hashCode(code),
        expiresAt,
        resendAvailableAt,
        resends: challenge.resends + 1,
        attempts: 0
      });
    } else {
      isNew = true;
      challenge = await OtpChallenge.create({
        phoneE164,
        sessionId,
        codeHash: hashCode(code),
        expiresAt,
        resendAvailableAt,
        provider: smsService.getProviderLabel()
      });
    }

    await smsService.sendOtp(phoneE164, code);
    return challengeResponse(res, challenge, isNew ? 201 : 200);
  } catch (error) {
    if (isNew && challenge) await challenge.destroy().catch(() => {});
    console.error('OTP request failed:', error.message);
    return res.status(503).json({ error: 'Failed to send verification code' });
  }
});

router.post('/verify', [
  body('challengeId').isUUID(),
  body('phoneE164').matches(/^\+255\d{9}$/),
  body('sessionId').isString().trim().isLength({ min: 1, max: 128 }),
  body('code').isLength({ min: 6, max: 6 }).isNumeric()
], async (req, res) => {
  if (validationErrors(req, res)) return;
  const { challengeId, phoneE164, sessionId, code } = req.body;

  try {
    const challenge = await OtpChallenge.findOne({
      where: { id: challengeId, phoneE164, sessionId }
    });
    if (!challenge) return res.status(404).json({ error: 'Challenge not found' });
    if (challenge.verified) return res.status(409).json({ error: 'Code already verified' });
    if (challenge.isExpired()) return res.status(410).json({ error: 'Code has expired' });
    if (!challenge.hasAttemptsLeft(MAX_ATTEMPTS)) {
      return res.status(423).json({ error: 'Too many attempts', attemptsRemaining: 0 });
    }

    const attempts = challenge.attempts + 1;
    await challenge.update({ attempts });
    const submittedHash = Buffer.from(hashCode(code), 'hex');
    const storedHash = Buffer.from(challenge.codeHash, 'hex');
    const matches = submittedHash.length === storedHash.length &&
      crypto.timingSafeEqual(submittedHash, storedHash);
    if (!matches) {
      const attemptsRemaining = Math.max(0, MAX_ATTEMPTS - attempts);
      return res.status(400).json({ error: 'Invalid code', attemptsRemaining });
    }

    await challenge.update({ verified: true });
    return res.json({
      message: 'Phone verified successfully',
      challengeId: challenge.id,
      phoneE164,
      sessionId,
      verifiedAt: new Date().toISOString()
    });
  } catch (error) {
    console.error('OTP verification failed:', error.message);
    return res.status(500).json({ error: 'Verification failed' });
  }
});

router.post('/resend', [
  body('challengeId').isUUID(),
  body('sessionId').isString().trim().isLength({ min: 1, max: 128 })
], async (req, res) => {
  if (validationErrors(req, res)) return;
  if (!validateProvider(res)) return;
  const { challengeId, sessionId } = req.body;

  try {
    const challenge = await OtpChallenge.findOne({
      where: { id: challengeId, sessionId, consumedAt: null }
    });
    if (!challenge) return res.status(404).json({ error: 'Challenge not found' });
    if (challenge.verified) return res.status(409).json({ error: 'Code already verified' });
    if (!challenge.canResend()) {
      const retryAfter = Math.ceil((challenge.resendAvailableAt - new Date()) / 1000);
      return res.status(429).json({ error: 'Too many requests', retryAfter });
    }
    if (!challenge.hasResendsLeft(MAX_RESENDS)) {
      return res.status(429).json({ error: 'Resend limit exceeded' });
    }

    const now = new Date();
    const code = generateCode();
    await challenge.update({
      codeHash: hashCode(code),
      expiresAt: new Date(now.getTime() + CODE_EXPIRY_SECONDS * 1000),
      resendAvailableAt: new Date(now.getTime() + RESEND_COOLDOWN_SECONDS * 1000),
      resends: challenge.resends + 1,
      attempts: 0
    });
    await smsService.sendOtp(challenge.phoneE164, code);
    return challengeResponse(res, challenge);
  } catch (error) {
    console.error('OTP resend failed:', error.message);
    return res.status(503).json({ error: 'Failed to resend code' });
  }
});

module.exports = router;