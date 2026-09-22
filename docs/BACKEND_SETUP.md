# Backend Setup

## SQLite API

1. Install Node.js 20 or newer.
2. From `heavenlink-backend`, install packages with `npm install`.
3. Copy `.env.example` to `.env` and set a strong, unique `JWT_SECRET` and `OTP_SECRET` (at least 32 random characters each).
4. Leave `SMS_PROVIDER=none` until a provider account is ready. The API refuses OTP requests while SMS is unconfigured.
5. Start the API with `npm run dev` for development or `npm start` for a normal run.

The database defaults to `heavenlink-backend/data/havenlink.sqlite`. Set `SQLITE_STORAGE` to an absolute path when the process working directory may differ. The initial schema is synchronized on startup. Back up the SQLite file before upgrades; automatic conversion from the former PostgreSQL database is not provided.

The admin dashboard can change the contact-unlock fee and accommodation service-fee rate. Values persist in SQLite and are read again by checkout and server-side booking/payment calculations.

## SMS OTP

Configure one supported provider in the backend environment:

- Twilio: `SMS_PROVIDER=twilio`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_PHONE_NUMBER`.
- Africa's Talking: `SMS_PROVIDER=africastalking`, `AFRICASTALKING_USERNAME`, and `AFRICASTALKING_API_KEY`.

Confirm Tanzanian destination and sender-ID access with the provider before production use. OTP values are generated on the server, stored as HMAC hashes, expire according to `OTP_CODE_TTL`, and are limited by attempt/resend policy. Never enable a local code logger or expose verification codes in logs.

## Flutter API URL

Pass the API origin at build/run time; do not add provider secrets to Flutter:

```powershell
flutter run -d chrome --dart-define=HAVEN_API_BASE_URL=http://localhost:3000
```

For the Android emulator, use `http://10.0.2.2:3000`. For a physical device, use the development computer's reachable LAN address and configure CORS accordingly. Flutter sends `/api/v1/...` paths to that origin.

Without an API URL, debug builds use clearly labelled local previews. Release builds show no seeded accounts/listings and cannot register or sign in.

## API Areas

- `/api/v1/auth`: registration, sign-in, profile, and server-issued bearer tokens.
- `/api/v1/otp`: request, verify and resend phone challenges.
- `/api/v1/properties`: public listings, agent listing writes, reports, saved properties, and post-unlock contact access.
- `/api/v1/bookings`: date/guest booking creation, availability and customer booking history.
- `/api/v1/payments`: separate rental-unlock and accommodation transaction types, transaction history and unlock records.
- `/api/v1/agents`: agent listings, bookings, room types, inventory, check-in policy and guest messages.
- `/api/v1/admin`: user/listing moderation, transactions, audit events and persisted business-fee configuration.

All private actions require a bearer token and are checked again by the backend. Public rental responses never include the protected owner contact or exact address.

## Not Production-Ready Yet

- SMS is unavailable until real credentials, sender permissions and delivery are configured and tested.
- M-Pesa, Airtel Money, Tigo Pesa and card payments are deliberately not advertised or accepted. Do not set client payment-method build flags until a complete provider initiation, authenticated callback and server-to-server status verification path has been implemented and tested.
- Listing forms accept secure image URLs, but multipart photograph upload/storage is not implemented.
- Stay-agent screens for room-type/inventory editing and guest communications still need Flutter API wiring; the backend persistence endpoints exist, but those UI panels are not yet end-to-end.
- The audit-event API persists administrator actions, but the dashboard does not yet include an audit-log viewer. Fraud reports, refund operations and full admin transaction workflows also need UI completion.
- Agent profile, inquiry, notification and guest-message Flutter flows still use local state rather than the backend records.
- The admin dashboard can update user roles/capabilities, enable or suspend accounts, moderate listings and persist fees; public registration cannot request `ADMIN`.
- Review backups, production migrations, HTTPS, CORS origins, rate limits and provider webhooks before deployment.
