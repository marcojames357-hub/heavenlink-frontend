# Connected local demo and design cross-check

The working preview is **http://localhost:8080**. Its API is
**http://localhost:3001/health**. Refresh an already open browser tab with
Ctrl+F5 after a rebuild.

## Why the earlier preview looked empty

The earlier release had no `HAVEN_API_BASE_URL`, so Flutter intentionally chose
its disconnected release repositories. Starting an API alone could not change
that compiled configuration. This preview is now built with:

```powershell
C:\flutter\bin\flutter.bat build web --no-pub --no-wasm-dry-run --dart-define=HAVEN_API_BASE_URL=http://localhost:3001 --dart-define=HAVEN_DEMO_MODE=true
node tool/start_demo.js
node tool/check_demo.js
```

For a fresh clone, first run `npm ci` in `heavenlink-backend` and
`flutter pub get` in the repository root. Run the commands above from the
repository root. The installed SDK matches the
project's pinned Flutter version. `start_demo.js` rejects a disconnected build,
checks the isolated database marker, starts missing local services with hidden
windows, and leaves unrelated services/processes untouched. Existing correct
services are reused. It never resets the normal database or edits `.env`.
The VS Code connected-demo launch configuration passes the same API/demo flags;
start the demo API before using that configuration.

## Demo accounts

Initial password for every account: **`HavenDemo!2026`**.

| Workspace | Email |
|---|---|
| Customer | `customer@demo.havenlink.test` |
| Rental Agent | `rental@demo.havenlink.test` |
| Apartment Stays Agent | `apartment@demo.havenlink.test` |
| Hotel / Lodge / Motel Agent | `hotel@demo.havenlink.test` |
| System Admin | `admin@demo.havenlink.test` |

These fictional accounts belong only to `heavenlink-backend/data/havenlink-demo.sqlite`.
The database includes ten published sample properties, eight room categories,
eight floors, sixteen physical rooms, three protected rental contacts and two
saved properties. It does not fabricate paid transactions, paid unlocks, reviews,
booking receipts or booking confirmations. The visible demo banner distinguishes
this environment from a normal build.

New registrations still require the existing SMS verification process. The
isolated demo API deliberately disables SMS sending and preserves the provider
unavailable response; use the pre-created accounts to inspect portals. A real
SMS provider must be configured and delivery tested for real sign-ups. Payment
providers remain disabled; no real charges can be made in this demo.

## Corrections from the Figma cross-check

- Registration now follows the reference's split brand panel, restrained glow,
  460px form card, external uppercase labels, tabs, field order and inline
  workspace selector. Four explicit choices are supported: Customer, Rental
  Agent, Apartment Stays Agent and Hotel/Lodge/Motel Agent. Optional multiple
  workspaces are preserved. Account creation still happens only after verified
  OTP; public registration cannot grant administrator access.
- Homepage hero now follows the reference proportions, 40px split gap and large
  heading. Date selection feeds the existing stay/room flow. Section anchors
  work after scrolling, and navigation adapts before the toolbar overflows.
  Discovery keeps its card/map composition without invalid intrinsic sizing.
- The default price filter no longer hides affordable stays such as the demo
  motel priced at TZS 60,000. Price selection and booking calculations remain
  separate; booking/payment rules were not changed.
- Rental details have the reference-style mosaic when enough real listing
  photos exist, and the sidebar shows the current configured unlock fee and
  verification note. Exact rental locations and contacts remain protected.
- Agent/admin overview compositions now include the chart/priority column and
  records table. Charts reflect actual listing counts by category; the export's
  hardcoded revenue/priority examples are not represented as real transactions.
- The existing system palette remains authoritative. These changes retain the
  repositories, services, distinct portals and authorization checks.

The export provides detailed reference compositions for home/auth/property
flows and portal overviews, but not every operational tab or dialog. Those
screens retain their existing workflows and use the shared styling. No claim of
pixel-exact parity for absent reference frames or every browser/device is made.

## Backend bug found by live checks

`GET /api/v1/bookings` returned HTTP 500 because its eager-loaded `roomType`
association was missing from the Sequelize association setup. Added the existing
Booking-to-RoomType relationship and a regression test that checks customer
history ownership and both room associations. This does not introduce a new
database column or change booking rules.

The original `data/havenlink.sqlite` was backed up and its SHA-256 was checked
before and after this continuation: it is unchanged. The normal `.env` is
unchanged. Demo startup is bound to 127.0.0.1 and uses fresh demo-only signing
secrets, so signing in again after a demo API restart is expected.

## Verification

- Flutter analysis: no issues found.
- Flutter suite: **96 passed**; includes registration types/OTP preservation,
  responsive layouts, source-derived fidelity checks and portal navigation.
- Backend suite: **114 passed** across ten suites. A longer timeout was used
  after this machine exceeded short database-initialization timeouts.
- Connected release web build succeeded with the explicit API/demo flags.
- Live HTTP smoke checks passed: ten public listings, CORS for the web preview,
  all five logins, agent-owned listing counts, hotel room endpoint, admin
  dashboard, customer booking history, customer/admin separation and locked
  rental contacts. The served JavaScript includes the correct API URL and demo
  marker. SMS unavailability is checked rather than bypassed.
- Registration desktop/mobile previews and dashboard layouts were visually
  inspected. Screenshots are under `../migration-backups/previews/`.

Logs and the live summary are under `../migration-backups/backend-demo-audit/`.
No public deployment, live SMS delivery or real payment was performed.

Final artifact check confirmed the refreshed JavaScript contains the explicit
API URL and current demo notice, and no longer contains the stale registration
punctuation. A previous incremental artifact was stale; the compilation cache
was moved to a reversible workspace backup and the connected release was rebuilt
from current source. Final smoke checks were run against the served artifact.
