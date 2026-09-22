const axios = require('axios');
const { PaymentTransaction } = require('../models');

class PaymentService {
  constructor() {
    this.methods = this.getAvailableMethods();
  }

  getAvailableMethods() {
    return [];
  }

  async createTransaction(purpose, amountTzs, methodId, customerId, listingId = null, bookingId = null, idempotencyKey = null) {
    const method = this.methods.find(m => m.id === methodId);
    if (!method) {
      throw new Error('Payment method not available');
    }

    const reference = this.generateReference();

    try {
      let providerResponse;
      switch (method.provider) {
        case 'mpesa':
          providerResponse = await this.initiateMpesaPayment(amountTzs, customerId, reference);
          break;
        case 'airtel':
          providerResponse = await this.initiateAirtelPayment(amountTzs, customerId, reference);
          break;
        case 'tigopesa':
          providerResponse = await this.initiateTigoPayment(amountTzs, customerId, reference);
          break;
        case 'stripe':
          providerResponse = await this.initiateStripePayment(amountTzs, customerId, reference);
          break;
        default:
          throw new Error('Payment provider not configured');
      }

      const transaction = await PaymentTransaction.create({
        reference,
        purpose,
        amountTzs,
        currency: 'TZS',
        methodId,
        customerId,
        listingId,
        bookingId,
        idempotencyKey,
        status: 'pending',
        providerResponse
      });

      return transaction;
    } catch (error) {
      console.error('Payment creation error:', error);
      throw new Error('Failed to create payment transaction');
    }
  }

  async verifyTransaction(transactionId) {
    const transaction = await PaymentTransaction.findByPk(transactionId);
    if (!transaction) {
      throw new Error('Transaction not found');
    }

    try {
      let providerStatus;
      switch (transaction.methodId) {
        case 'mpesa':
          providerStatus = await this.checkMpesaStatus(transaction.reference);
          break;
        case 'airtel':
          providerStatus = await this.checkAirtelStatus(transaction.reference);
          break;
        case 'tigopesa':
          providerStatus = await this.checkTigoStatus(transaction.reference);
          break;
        case 'card':
          providerStatus = await this.checkStripeStatus(transaction.providerResponse?.paymentIntentId);
          break;
        default:
          throw new Error('Payment method not supported');
      }

      if (providerStatus.success) {
        await transaction.update({
          status: 'succeeded',
          verifiedAt: new Date(),
          providerResponse: { ...transaction.providerResponse, ...providerStatus }
        });
      } else {
        await transaction.update({
          status: 'failed',
          failureMessage: providerStatus.message || 'Payment failed',
          providerResponse: { ...transaction.providerResponse, ...providerStatus }
        });
      }

      return transaction;
    } catch (error) {
      console.error('Payment verification error:', error);
      throw new Error('Failed to verify payment status');
    }
  }

  async initiateMpesaPayment(amount, customerId, reference) {
    // M-Pesa STK Push implementation
    const consumerKey = process.env.MPESA_CONSUMER_KEY;
    const consumerSecret = process.env.MPESA_CONSUMER_SECRET;
    const passkey = process.env.MPESA_PASSKEY;
    const shortcode = process.env.MPESA_SHORTCODE;

    // Generate auth token
    const auth = Buffer.from(`${consumerKey}:${consumerSecret}`).toString('base64');
    const tokenResponse = await axios.get(
      'https://api.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
      { headers: { Authorization: `Basic ${auth}` } }
    );

    const token = tokenResponse.data.access_token;
    const timestamp = new Date().toISOString().replace(/[:.]/g, '').slice(0, -3);
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

    const stkPushResponse = await axios.post(
      'https://api.safaricom.co.ke/mpesa/stkpush/v1/processrequest',
      {
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: amount,
        PartyA: customerId, // Should be phone number
        PartyB: shortcode,
        PhoneNumber: customerId,
        CallBackURL: `${process.env.CALLBACK_URL}/api/v1/payments/mpesa/callback`,
        AccountReference: reference,
        TransactionDesc: 'Haven Link Payment'
      },
      { headers: { Authorization: `Bearer ${token}` } }
    );

    return {
      success: true,
      merchantRequestID: stkPushResponse.data.MerchantRequestID,
      checkoutRequestID: stkPushResponse.data.CheckoutRequestID,
      paymentIntentId: stkPushResponse.data.CheckoutRequestID
    };
  }

  async initiateAirtelPayment(amount, customerId, reference) {
    // Airtel Money implementation
    const response = await axios.post(
      'https://payments-api.airtel.com/merchant/v1/payments',
      {
        reference: reference,
        subscriber: {
          country: 'TZ',
          currency: 'TZS',
          msisdn: customerId
        },
        transaction: {
          amount: amount,
          country: 'TZ',
          currency: 'TZS',
          id: reference
        }
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Id': process.env.AIRTEL_MONEY_CLIENT_ID,
          'X-Client-Secret': process.env.AIRTEL_MONEY_CLIENT_SECRET
        }
      }
    );

    return {
      success: true,
      transactionId: response.data.data.transaction_id,
      paymentIntentId: response.data.data.transaction_id
    };
  }

  async initiateTigoPayment(amount, customerId, reference) {
    throw new Error('Tigo Pesa integration is not configured');
  }

  async initiateStripePayment(amount, customerId, reference) {
    const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // Amount in cents
      currency: 'TZS',
      metadata: { reference, customerId },
      description: 'Haven Link Payment'
    });

    return {
      success: true,
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id
    };
  }

  async checkMpesaStatus(reference) {
    // Check M-Pesa transaction status
    // This would query M-Pesa API using the checkout request ID
    throw new Error('M-Pesa status verification is not configured');
  }

  async checkAirtelStatus(reference) {
    // Check Airtel transaction status
    throw new Error('Airtel Money status verification is not configured');
  }

  async checkTigoStatus(reference) {
    // Check Tigo transaction status
    throw new Error('Tigo Pesa status verification is not configured');
  }

  async checkStripeStatus(paymentIntentId) {
    const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

    return {
      success: paymentIntent.status === 'succeeded',
      message: paymentIntent.status
    };
  }

  generateReference() {
    return `HL-${Date.now()}-${Math.random().toString(36).substr(2, 9).toUpperCase()}`;
  }

  isConfigured() {
    return false;
  }
}

module.exports = new PaymentService();
