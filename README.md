
# Haven Link

Haven Link is a Flutter property discovery and booking application for Tanzania. It has two distinct customer paths:

- **Stays:** hotels, lodges and short-stay apartments can be booked directly.
- **Rentals:** houses and rooms are discovered publicly; exact addresses and verified owner or authorized agent contacts remain locked until an unlock payment is confirmed.

## Run

Install Flutter stable, then from this directory run:

```powershell
flutter pub get
flutter run -d chrome
```

For an Android device or emulator, use `flutter run`; use `flutter devices` to list available targets. iOS builds require macOS and Xcode.

## Structure

- `lib/core/` contains theme, business configuration, formatting and customer state.
- `lib/features/` contains property data, search, auth, account, payment and checkout workflows.
- `lib/features/properties/data/property_repository.dart` selects the SQLite-backed API repository when configured and a debug-only preview repository otherwise.
- `test/` covers the launch, separate search models, TZS totals and rental unlock privacy/payment flow.

## Backend

The backend API uses SQLite by default and stores its data in `heavenlink-backend/data/havenlink.sqlite`. Set `SQLITE_STORAGE` to choose another file. Follow [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md) to configure the API and point Flutter at it.

The debug preview uses seeded listings, local accounts and clearly labelled non-payment flows. Release builds without a backend do not use demo accounts or demo listings. SMS delivery requires a configured Twilio or Africa's Talking account. Payment rails are currently disabled until a provider adapter and server-side verification are configured and tested. Listing images currently use HTTPS URLs; binary photo upload is not implemented.
  