
# Haven Link

Haven Link is a Flutter property discovery and booking application for Tanzania. It has two distinct customer paths:

- **Stays:** hotels, lodges and short-stay apartments can be booked directly.
- **Rentals:** houses and rooms are discovered publicly; exact addresses and verified owner or authorized agent contacts remain locked until an unlock payment is confirmed.

## Connected local demo

Use [docs/CONNECTED_DEMO.md](docs/CONNECTED_DEMO.md) for the backend-connected
preview, sample property data and five portal logins. It uses an isolated demo
SQLite database and explicit API build flags; a release built without an API
URL will remain disconnected. Existing application data is left unchanged.

## Run

Use the project-pinned Flutter SDK (3.47.9). Install FVM once with
`dart pub global activate fvm`, then from this directory run:

```powershell
fvm install
fvm flutter pub get
fvm flutter run -d chrome
```

On Windows, reopen VS Code after installing FVM or adding
`%LOCALAPPDATA%\Pub\Cache\bin` to your user `Path`. If FVM cannot create its
SDK link, enable Developer Mode in **Settings > System > For developers** (or
run the terminal as administrator), then rerun `fvm install`.

The VS Code workspace uses the same FVM SDK. The minimum supported SDKs are
Flutter 3.44.0 and Dart 3.12.1, matching the package lockfile. Use `fvm flutter`
for tests and builds as well so local commands and the editor do not resolve
different Flutter/Dart versions.

For an Android device or emulator, use `fvm flutter run`; use
`fvm flutter devices` to list available targets. iOS builds require macOS and
Xcode.

Agents must be at the property and allow device location access when adding a rental or stay listing. The editor captures the device's reported coordinates automatically; use **Use current location** to retry or update an existing listing's location. Existing listing coordinates remain unchanged unless recaptured. Location accuracy varies by device and surroundings, and device location alone cannot verify physical presence. Web location requires HTTPS or localhost and browser permission.

For iOS builds with Swift Package Manager, set `BYPASS_PERMISSION_LOCATION_ALWAYS=1` in the build environment so the location plugin requests only when-in-use access (for example, `BYPASS_PERMISSION_LOCATION_ALWAYS=1 fvm flutter build ios` on macOS).

## Structure

- `lib/core/` contains theme, business configuration, formatting and customer state.
- `lib/features/` contains property data, search, auth, account, payment and checkout workflows.
- `lib/features/properties/data/property_repository.dart` selects the SQLite-backed API repository when configured and a debug-only preview repository otherwise.
- `test/` covers the launch, separate search models, TZS totals and rental unlock privacy/payment flow.

The visual theme uses the supplied design's teal (`#0B806B`), dark green
(`#123B35`), pale green and white palette. Shared portal navigation and
workspace styling live under `lib/core/widgets/`.

## Backend

The backend API uses SQLite by default and stores its data in `heavenlink-backend/data/havenlink.sqlite`. Set `SQLITE_STORAGE` to choose another file. Follow [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md) to configure the API and point Flutter at it.

Without a backend, debug builds start with no sample listings or pre-created accounts. Test fixtures live in the test suite only. Clearly labelled local OTP and payment previews remain available for development; they do not send messages or move money. SMS delivery requires a configured Twilio or Africa's Talking account. Payment rails are currently disabled until a provider adapter and server-side verification are configured and tested. Listing images currently use HTTPS URLs; binary photo upload is not implemented.
  