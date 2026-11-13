# Backend Setup

## SQLite API

1. Install Node.js 20 or newer.
2. From `heavenlink-backend`, install packages with `npm install`.
3. Copy `.env.example` to `.env` and set a strong, unique `JWT_SECRET` and `OTP_SECRET` (at least 32 random characters each).
4. Leave `SMS_PROVIDER=none` until a provider account is ready. The API refuses OTP requests while SMS is unconfigured.
5. Start the API with `npm run dev` for development or `npm start` for a normal run.

The database defaults to `heavenlink-backend/data/havenlink.sqlite`. Set `SQLITE_STORAGE` to an absolute path when the process working directory may differ. Missing tables and location columns are added on startup; existing tables are not destructively altered. Back up the SQLite file before upgrades; automatic conversion from the former PostgreSQL database is not provided.

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
- `/api/v1/reviews`: completed-stay eligibility, guest review submission, public review summaries, and reporting.
- `/api/v1/payments`: separate rental-unlock and accommodation transaction types, transaction history and unlock records.
- `/api/v1/agents`: agent listings, bookings, room types, inventory, check-in policy, booking conversations and unlock-gated rental conversations.
- `/api/v1/admin`: user/listing moderation, transactions, audit events and persisted business-fee configuration.

All private actions require a bearer token and are checked again by the backend. Public rental responses never include the protected owner contact or exact address.
Password recovery is not available yet; the API does not expose a password-reset endpoint.

## Booking messages

The existing booking-message API is restricted to the booking customer and the
agent authorized to manage that stay. Access requires a verified accommodation
payment matching the booking, customer, and booking total; pending bookings and
failed or unverified payments do not grant access. Administrators do not have
automatic access to private conversations.

New messages are allowed for confirmed bookings and for 14 days after a
recorded checkout on completed bookings by default. Configure this period with
`STAY_MESSAGE_FOLLOW_UP_DAYS` (an integer from 1 to 365) and restart the API.
Cancelled or refunded bookings cannot
receive new messages; participants can still read their history if the
previously verified payment is recorded. Messages are rate-limited and create
an in-app notification for the other participant.

Rental conversations are scoped to one customer and one contact-unlock listing.
The API rechecks the active unlock and its succeeded, verified payment on every
read and send; a refund or revoked unlock blocks further access. Only the
customer and the listing's authorized Rental Agent can access that conversation.
The customer account and Rental Agent Portal expose the corresponding inboxes.

## Stay review eligibility

New stay reviews require a completed checkout within the 14-day review window
and a succeeded, verified accommodation payment linked to the same booking,
customer and total. Refunded, failed, missing and mismatched payments do not
qualify. Trip payment status reflects the recorded payment instead of assuming
that a transaction link means verified payment. Review invitations are sent
only when the booking has a matching verified payment.

Legacy bookings without matching payment records are not eligible for new
reviews; existing published reviews are not removed. Earlier database
upgrades may have populated checkout times for old completed bookings, so
operators should review those historical records before treating them as proof
of an actual checkout. No legacy payment records are fabricated by this change.

## Platform modernization sequence

The application has explicit RENTAL, APARTMENT and HOTEL workspace grants,
separate agent portals and inventory flows. Legacy stay-agent access is reviewed
through workspace grants and authorization checks. Continue using the existing
booking, financial, notification, review and report components as the
foundation for remaining work, including a verified payment provider and
receipts. Each production change requires migration and authorization tests.
The stay-agent portal now uses grouped sidebar/drawer navigation with active
section highlighting and breadcrumbs (Main, Property Management, Business
Management and Account). This preserves the existing Haven Link styling while
replacing the former flat tab row for better desktop/mobile organization.
Accommodation create/edit now includes a step-based flow with progress, step
switching, previous/next controls and explicit draft saving; existing field
validation and inventory-model confirmation behavior are unchanged. Room
category and physical-room setup is still a guided handoff to the inventory
section after the property is saved; incomplete partial-field drafts are not
supported by the current required-field schema.

## Multi-room Stays Inventory

Hotels, motels and lodges use one public property listing with internally generated physical rooms. Existing apartment and shared-room properties remain on their aggregate room-type inventory path. Stay agents can generate floors and room numbers, create room categories, bulk-assign rooms, and block maintenance dates through `/api/v1/agents/rooms`; blocked dates cannot overlap a confirmed reservation or an active checkout hold. Category assignment checks reservations and planned category capacity inside the same immediate transaction as the update, preventing simultaneous bookings or assignments from bypassing those checks. Booking creation and availability checks exclude conflicting reservations, active holds, out-of-service rooms and maintenance blocks. A selected room category is allocated server-side, with a temporary hold expiring after 15 minutes until payment is verified.

The Flutter room-category editor currently accepts secure photo URLs; multipart room-photo upload/storage is not implemented. Agents can add floorless rooms using real-world identifiers, edit room identifiers, assign categories, and manage per-room maintenance blocks. Manual, edited, and generated identifiers must be valid and unique within a property, ignoring case; changes are audited. Generated rooms remain unassigned until the agent assigns a category. Room and category creation rechecks the inventory model inside the write transaction so a concurrent model change cannot attach inventory to the wrong model.

Property-wide and room-category amenities support optional descriptions in the
`amenityDetails` JSON array (`name`, optional `description`). Existing
`amenities` string arrays remain intact for compatibility. The agent forms
support predefined facility chips and custom newline entries in
`name | description` format; public property and stay-info responses render
descriptions as escaped text. Startup adds the two JSON columns additively to
existing SQLite databases, defaulting existing properties and categories to
empty detail arrays without rewriting legacy amenity data.

The inventory panel's shared date-range view combines online reservations,
temporary holds, walk-ins and maintenance blocks, with separate walk-in
occupancy labels. It uses UTC calendar dates and an exclusive end date, and
limits requests to 93 days. Walk-in room changes split occupancy into dated
room segments, so the calendar shows the correct room for each part of the
stay and only the currently occupied room receives the checked-in label. This
is a room-by-room timeline, not yet a full interactive calendar: online
check-in occupancy, reservation details and authorized booking reassignment
are not implemented.

Property changes between entire-unit and hotel-style inventory require an
explicit confirmation, are audited, and are rejected if any booking history,
walk-in, room, or room category exists. Existing data is not restructured or
deleted; an operator must review such cases. Legacy hotel and lodge categories
without an `accommodationType` still require assigned active rooms before
publication. Category edits retain the price stored on existing bookings, and
cannot reduce planned room count below assigned rooms or capacity below an
active online reservation's guest count. Categories with assigned rooms or
reservation history cannot be deleted.

### Walk-in reservations

Authorized stay agents can record and manage walk-ins from the room inventory
screen. Walk-ins use a separate reservation record but share the same atomic
physical-room conflict checks as online holds, payment confirmation and
maintenance blocks. Room categories cannot be reassigned while a room has an
active walk-in. Reservations retain their history and creation/update audit
events; checked-in guests must be checked out rather than cancelled. A checked-in
guest past their expected departure continues to block the room until checkout.
Agents can change rooms within the same category; a required reason is audited,
and checked-in stays preserve their room-by-room occupancy history. The walk-in
list exposes that history for moved reservations. Legacy walk-ins are given an
initial room segment at startup without duplicating existing segments.

The manually entered walk-in payment status is an operational note, not a
verified online payment, financial receipt or reconciliation record. The current
walk-in management screen is a list; creation conflicts suggest up to five
available rooms in the same category. Use the connected API; local preview mode
does not simulate walk-ins.

## Apartment and hotel booking safeguards

Serviced and short-stay apartments are treated as one bookable unit, regardless
of bedroom count or the configured quantity of an associated room category.
The API creates an atomic 15-minute hold and rejects overlapping confirmed
stays or active holds. Adjacent stays are allowed. The availability API uses
the same apartment overlap rules. Hotels, motels and lodges require a room
category with assigned physical rooms for new bookings. A booking request key
may be retried only for the same customer and booking details; reuse for a
different request returns a conflict.

Bookings can only be confirmed through payment verification, not by directly
changing their status. A payment received after its hold has expired, or for
a cancelled booking, is not allowed to revive that booking. Such cases return
a conflict requiring manual support and reconciliation; automated refunds are
not implemented. Recorded checkouts before check-in are rejected. None of
these safeguards constitutes a configured payment provider.

A failed or expired payment releases a pending hold only when it is the
payment currently linked to that booking. An administrator verifying a rental
payment grants the unlock to the payment customer, not the administrator.

These safeguards do not add an apartment availability calendar, standalone
apartment guest-capacity field, walk-in workflow, or rental tenancy system.
Existing non-apartment aggregate room-type inventory still needs a unified,
atomic reservation implementation before production use.

## Property Locations

Agents can save a listing's latitude, longitude and formatted address through the listing API. Coordinates must be supplied as a valid pair, and listings cannot be published without coordinates. Location edits are marked pending verification and recorded in the audit log. Public rental list/detail responses omit exact coordinates and addresses; `GET /api/v1/properties/:id/location` requires an active unlock whose linked payment transaction succeeded and matches both the customer and listing. Stay coordinates are public only when the listing's `locationVisibility` is `exact`; the default is `approximate`. Startup adds missing location columns to existing SQLite databases without removing current data.

Property details now show a responsive Google Maps embed, using exact coordinates only where the listing visibility policy allows them. The shared agent form currently accepts manually entered coordinates; map-based pin placement, address autocomplete/reverse geocoding, nearby Places search and route estimates are not yet configured. Before adding those APIs, provision restricted Google Maps Platform keys, enable the required Maps, Places, Geocoding and Routes services, configure billing, and store server credentials only in backend environment variables. Do not put a server key in Flutter build defines or source control.

## Guest Reviews

Completed bookings for published bookable stays are eligible for one customer review. The backend validates all six ratings and booking ownership, and the unique booking index rejects duplicate submissions. Review and report tables are created additively by the existing Sequelize startup sync; back up the SQLite database before deploying schema changes. Published-review aggregates are read from the review rows so admin hide/restore actions immediately update property ratings, distributions and guest-mention counts. Admin moderation requires a reason and writes a `REVIEW_MODERATED` audit event. Customers can report published reviews; administrator queue and audit APIs are under `/api/v1/admin/reviews` and `/api/v1/admin/audit-events`.

Photo uploads are not available because multipart review-photo storage is not implemented. Review reminders are in-app only; this backend has no configured email delivery service.

## Not Production-Ready Yet

- SMS is unavailable until real credentials, sender permissions and delivery are configured and tested.
- M-Pesa, Airtel Money, Tigo Pesa and card payments are deliberately not advertised or accepted. Do not set client payment-method build flags until a complete provider initiation, authenticated callback and server-to-server status verification path has been implemented and tested.
- Listing forms accept secure image URLs, but multipart photograph upload/storage is not implemented.
- Nearby Places search and commute/routes are not implemented. The detail map uses a Google Maps embed and does not yet request provider routing or Places data.
- Agent booking-message API methods exist, but no agent inbox screen calls them yet. Broader availability-policy/calendar flows still need UI completion. Physical room generation, category editing and assignment, and maintenance date blocking are connected to the backend.
- The admin dashboard includes an audit-history viewer backed by `/api/v1/admin/audit-events`. Fraud reports, refund operations and full admin transaction workflows still need UI completion.
- Agent profile screens and customer rental conversations use backend records. Agent-side booking-message methods exist without an inbox screen, so agent inquiry and communication flows are not yet fully connected.
- The admin dashboard can update user roles/capabilities, enable or suspend accounts, moderate listings and persist fees; public registration cannot request `ADMIN`.
- Review backups, production migrations, HTTPS, CORS origins, rate limits and provider webhooks before deployment.
