# Local demo dataset

This dataset is fictional and intended for this computer only. It is completely
separate from `data/havenlink.sqlite`. It never sends SMS, initiates real payment,
fabricates verified payment records, or unlocks rental contacts without the
existing payment checks. Demo account verification is part of fixture creation;
no registration or OTP API is bypassed or weakened.

## Create or inspect

From the standalone `heavenlink-backend` directory:

```powershell
npm.cmd run seed:demo
npm.cmd run seed:demo -- --check
```

`--check` is read-only and validates the existing initialized dataset. It returns
a nonzero exit status if the demo database is absent or unsafe. The only accepted target
is this backend's `data/havenlink-demo.sqlite`, even if `.env` or the shell points
the normal application at a different SQLite file. `NODE_ENV=production` is
rejected. Linked/redirected paths, a non-demo database marker, and non-demo or
reassigned users/listings are rejected before model sync. A fresh demo database
receives a dataset marker before initialization.

The seed is additive and idempotent. Re-running it adds missing fixtures and
keeps existing fixture values, passwords and workspace revocations unchanged.
Do not delete or reset the ordinary database. If someone registers non-fixture
accounts or creates non-fixture properties in this demo file, later seed runs
refuse to mix in more fixture data; the existing data is left intact.

## Accounts

All newly created demo accounts use **`HavenDemo!2026`**. The `.test` addresses
and phone numbers are fictional; do not attempt SMS or contact these numbers.
These credentials must never be used for a deployed/public server.

| Workspace | Email |
|---|---|
| Customer | `customer@demo.havenlink.test` |
| Rental Agent | `rental@demo.havenlink.test` |
| Apartment Stays Agent | `apartment@demo.havenlink.test` |
| Hotel, Lodge and Motel Agent | `hotel@demo.havenlink.test` |
| System Admin | `admin@demo.havenlink.test` |

The account roles and explicit RENTAL/APARTMENT/HOTEL grants use the existing
server authorization model. Public registration still cannot request ADMIN.
If a demo password was subsequently changed, re-running the seed does not reset
it; the credentials above describe initial creation only.

## Fixture inventory

- Five users, three explicit agent workspace grants and three agent profiles.
- Ten published, clearly named demo properties: three monthly rentals, three
  whole-unit apartment stays, two hotels, one lodge and one motel.
- Eight room categories, eight floors and sixteen assigned physical rooms for
  the hotel/lodge/motel properties, plus their check-in policies.
- Three protected rental contacts and two saved properties for the demo customer.
- Zero fabricated guest reviews, bookings, payment transactions, receipts or
  paid rental unlocks. Ratings start at zero, and payment/provider limitations
  remain visible and enforced.

The motel uses the backend's existing `category=hotel` /
`accommodationType=motel` representation. Public API mapping returns the motel
category correctly. Apartments remain whole-unit stays without hotel room IDs.
Property photographs are illustrative Unsplash URLs, not proof of a real listing.

## Start the isolated backend

After creating the demo dataset, use the guarded local runtime:

```powershell
npm.cmd run demo:api
```

It binds to 127.0.0.1:3001, verifies the demo database marker, disables SMS, and
uses ephemeral demo-only signing secrets. It does not edit `.env` or open the
normal database. Build Flutter with `HAVEN_API_BASE_URL=http://localhost:3001`
and `HAVEN_DEMO_MODE=true`. The frontend guide `docs/CONNECTED_DEMO.md` includes
the connected launcher and full verification commands.

## Runtime guard API

The local demo launcher may import `validateRuntimeTarget()` from
`src/seedDemo.js` before loading Sequelize models. It verifies the exact local
demo path, non-production environment, dataset marker and initialized tables.
It intentionally permits app-created users/listings, so trying registration
does not prevent a later server restart. The stricter seeding guard still
refuses to seed a database containing non-fixture users or listings.
