const twilio = require('twilio');
const africastalking = require('africastalking');

class SmsService {
  constructor() {
    this.provider = process.env.SMS_PROVIDER || 'none';
    this.twilioClient = null;
    this.atClient = null;

    if (this.provider === 'twilio') {
      this.twilioClient = twilio(
        process.env.TWILIO_ACCOUNT_SID,
        process.env.TWILIO_AUTH_TOKEN
      );
    } else if (this.provider === 'africastalking') {
      const AT = africastalking({
        username: process.env.AFRICASTALKING_USERNAME,
        apiKey: process.env.AFRICASTALKING_API_KEY
      });
      this.atClient = AT.SMS;
    }
  }

  async sendOtp(phone, code) {
    const message = `Your Haven Link verification code is: ${code}. Valid for 5 minutes. Do not share this code with anyone.`;

    try {
      switch (this.provider) {
        case 'twilio':
          return await this.sendTwilioSms(phone, message);
        case 'africastalking':
          return await this.sendAfricaTalkingSms(phone, message);
        default:
          throw new Error('SMS provider is not configured');
      }
    } catch (error) {
      console.error('SMS sending error:', error);
      throw new Error('Failed to send SMS. Please try again.');
    }
  }

  async sendTwilioSms(phone, message) {
    try {
      const result = await this.twilioClient.messages.create({
        body: message,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: phone
      });
      return { success: true, provider: 'twilio', messageId: result.sid };
    } catch (error) {
      console.error('Twilio error:', error);
      throw error;
    }
  }

  async sendAfricaTalkingSms(phone, message) {
    try {
      const result = await this.atClient.send({
        to: phone,
        message: message,
        from: process.env.AFRICASTALKING_SENDER_ID || 'HavenLink'
      });
      return { success: true, provider: 'africastalking', messageId: result.SMSMessageData.Recipients[0].messageId };
    } catch (error) {
      console.error('Africa\'s Talking error:', error);
      throw error;
    }
  }

  isConfigured() {
    if (this.provider === 'twilio') {
      return !!(
        process.env.TWILIO_ACCOUNT_SID &&
        process.env.TWILIO_AUTH_TOKEN &&
        process.env.TWILIO_PHONE_NUMBER
      );
    }
    if (this.provider === 'africastalking') {
      return !!(process.env.AFRICASTALKING_USERNAME && process.env.AFRICASTALKING_API_KEY);
    }
    return false;
  }

  getProviderLabel() {
    switch (this.provider) {
      case 'twilio':
        return 'Twilio';
      case 'africastalking':
        return 'Africa\'s Talking';
      default:
        return 'Local development';
    }
  }
}

module.exports = new SmsService();
