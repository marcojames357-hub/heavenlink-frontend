# Figma Make → Flutter migration

## Scope and rollback (13 November 2026)

Preserve the current Flutter palette, business rules, APIs, and data. The Make
export is a read-only visual reference; its Payload backend is not a replacement
for Haven Link. The user subsequently expanded the scope to all pages and all
five portals, so carry the shared visual system through every existing workspace.

Git rollback base: `6c6ce83` (Add Haven Link backend API). The working tree already
contains substantial uncommitted functionality. A pre-edit snapshot of `lib/`,
`test/`, `docs/`, the pubspec files, analyzer settings and README is saved at
`../migration-backups/frontend-before-ui-migration-2026-11-13.zip`. Restore only
specific files from that archive when reverting this pass; do not reset the
working tree to the older commit. Backend/database files are outside this pass.

## Existing architecture

- Production Flutter root: `havenlink/heavenlink-frontend` (`pubspec.yaml`).
- Standalone Node/Express/Sequelize backend: `havenlink/heavenlink-backend`;
  a second, older backend copy exists inside the Flutter repository. Do not merge
  or modify these copies as part of styling. SQLite storage stays unchanged.
- `HavenLinkApp` owns locale and `HavenLinkStore`. `HavenLinkShell` switches
  customer tabs and pushes detail/auth/portal screens with MaterialPageRoute.
- State uses ChangeNotifier stores, constructor injection and existing
  repositories; no new state or routing package is needed.
- `core/data/api_client.dart`, auth/customer/property/agent/admin/review/finance
  repositories keep their real HTTP connections. Preview repositories remain
  development-only. `AccessControl` gates the separate agent/admin workspaces.
- Existing screens include home/search/details/multi-room stays; auth and OTP;
  checkout; account/bookings/receipts/rental conversations; notifications;
  reviews/problem reports; rental/apartment/hotel portals; listing editing;
  availability, physical rooms, walk-ins and room calendars; finances/tenancies;
  admin users, moderation, inventory, audit events and reports.
- Existing shared UI: HavenTheme, DesignTokens, HavenIcons, PropertyCard,
  PropertyPhoto, PortalSidebar and PortalPageHeader. Extend these, not duplicates.

## Reference structure and extracted visual system

Source: `Downloads/Design Havenlik Project (1)`.
`src/components/HavenLink.tsx` contains Brand, PublicHeader, HomePage,
PortalDashboard, StayPropertyFlow and RentalPropertyFlow. App routes cover home,
auth, customer/rental/stays/admin portals and two example property flows.
`styles.css` loads Inter 400/500/600/700/800. `.figma/` contains Make lifecycle
configuration, not exported design frames. `public/` contains only a generic
favicon. Property photography is remote Unsplash imagery in the TSX; do not
copy example properties, review scores or photos over real listing records.
There is no separate apartment portal design or complete design for every
existing operational screen.

| Token | Reference | Migration decision |
|---|---|---|
| Typography | Inter; body 10–14; section 28/34; hero 42/58/68; weights 400–800 | Keep Inter; use readable Flutter labels, responsive hero scale, 1.05–1.5 line height |
| Letter spacing | Tight headings (-.04/-.055em); uppercase kickers .16em | Apply selectively, preserve text scaling |
| Colors | Teal #0B806B, dark #123B35, mint #72D9C2, white, pale mint; muted #718681, border #DCE9E5, gold #EDAA2F | Current HavenTheme constants are authoritative; no palette changes |
| Spacing | 4/8/12/16/20/24/32, section 64/80 | Reuse DesignTokens and responsive padding |
| Shape | Buttons 12, cards 16/20/22, hero 28/32, pill badges | Centralize home layout values in DesignTokens |
| Layout | Header 76, max width 1320, split hero, 2/3/5 category columns | Adapt to available width; retain mobile bottom navigation |
| Effects | Subtle shadows, hover lift, 200ms transitions | Native Material focus/hover/pressed states; restrained animation |
| Icons/assets | Lucide; Home brand mark; remote example photos | Reuse HavenIcons and real PropertyPhoto; no new image dependency |

## Screen mapping and preservation strategy

| Figma | Existing Flutter | Action |
|---|---|---|
| PublicHeader / Brand | HavenLinkShell | Reuse responsive header and auth/locale/account actions |
| HomePage hero / search | HomeScreen / _HeroPanel | Restyle, connect query/category search to existing browse screen |
| Five category cards | HomeScreen | Add native adaptive cards; route into existing category filters |
| Discovery cards | PropertyCard / browse screen | Reuse real records, saved state, verification and prices |
| MiniMap | PropertyMap / detail screen | Keep real detail maps; omit decorative fake homepage pins |
| Trust / portal / footer sections | HomeScreen / AccessControl | Add informational sections; approved workspaces retain existing navigation |
| Customer dashboard / auth | AccountScreen / AuthScreen / OTP | Later: apply shared components without losing receipts, reports or messaging |
| StayPropertyFlow | Detail / MultiRoomStay / Checkout | Later: preserve room selection, holds, totals and verified-payment gates |
| RentalPropertyFlow | PropertyDetailScreen | Later: preserve contact/location unlock; no stay reviews/bookings |
| Rental PortalDashboard | RentalAgentDashboardScreen | Later: keep tenancy, utilities, finance workflows separate |
| Stays PortalDashboard | Apartment / accommodation dashboards | Later: style independently; preserve inventory and check-in rules |
| Admin PortalDashboard | AdminDashboardScreen and tabs | Later: retain moderation, audit and authorization |

Figma includes unsupported or misleading placeholders (100% verification,
configured payments, sample ratings, fake map pins, fixed dates, unrestricted
portal previews). Translate visual composition while retaining truthful state
and existing authorization. Do not implement new provider APIs or business rules.
Dark mode has no reference or current product control; defer a complete dark
palette rather than changing the user's current colors during this phase.

## Components and dependencies

Extend HavenTheme/DesignTokens; retain Material 3 form/button/dialog behavior,
Inter via google_fonts, Lucide via HavenIcons, and the existing FlexColorScheme
and ShadTheme wrappers. No package additions or upgrades are required. Use
LayoutBuilder, Wrap and native Material ink/focus states instead of introducing
another component, animation or responsive framework. Share section headings,
category tiles and home search controls within the existing presentation layer.

## Ordered implementation / validation

1. Audit and snapshot; document this mapping before UI edits.
2. Finish home search/category discovery and shared layout tokens; preserve
   existing live featured cards, stay/rental sections and error/retry states.
3. Validate format, analyze, relevant tests, full tests and web compilation;
   exercise phone/tablet/desktop layouts and query/category navigation.
4. Report phase 1–2 results for review before implementing later phases.
5. Later phases: discovery/details → account/checkout → rental portal → apartment
   portal → hotel portal → admin → cross-platform consistency/accessibility audit.

Installed SDK `C:/flutter` reports Flutter 3.47.9 / Dart 3.13.7, matching `.fvmrc`.
The `.fvm/flutter_sdk` link is missing; validation uses the installed SDK directly.
Bundled assets require an asset-manifest refresh; `flutter pub get --offline`
was executed successfully. No package versions were deliberately changed.

## Implementation record

- Home: responsive split hero, compact query/type search connected to existing
  browse filters, five categories, filtering discovery cards, public area map,
  trust journeys, approved-workspace entries, invitation photo and footer.
  Section backgrounds span the viewport with a 1320px content constraint.
  Real listing data, save actions, retry/loading and navigation stay connected.
- Theme: bundled Inter variable font (400–800), native controls, responsive
  dropdowns, table/calendar/drawer styles and shared metric cards. Existing
  HavenTheme palette constants are unchanged. The Make CSS generic italic serif
  accent uses bundled Libre Caslon Text for consistent Flutter rendering; this
  is a font substitution, not a claim of an exact Georgia match.
- Portals: full-height 250px management sidebar, content-only 70px header,
  working destination search, user initials and existing primary actions.
  Customer navigation uses the same header/metrics. Rental, apartment,
  hotel/lodge/motel and admin callbacks and permissions remain separate.
- Booking: hotel selection and room reservation use desktop content/booking
  columns and mobile stacking. Room details, availability, guest limits and
  payment paths stay intact. Checkout adapts the existing form/summary; rental
  unlock does not show stay-booking steps.
- Property cards retain listing imagery, verification, prices and save actions.
  Missing photos use placeholders. Decorative hero photography is only a
  no-listing fallback and never represents a specific missing listing photo.
- Operational tabs, notifications, reviews, finances, inventory and editors keep
  their content and repositories, receiving the shared theme and responsive
  controls. Most detailed operational screens have no standalone Figma layout;
  their styling follows the reference design system.
- Validation exposed unobserved errors from lazy review/audit futures. Observe
  them immediately while preserving their FutureBuilder error states. Missing
  admin listing photos use the existing error-safe PropertyPhoto component.
  No authorization checks or backend behavior changed.

## Asset provenance

- Inter: Google Fonts repository, `ofl/inter/Inter[opsz,wght].ttf`;
  license: `assets/fonts/OFL.txt`.
- Libre Caslon Text italic: Google Fonts repository,
  `ofl/librecaslontext/LibreCaslonText-Italic[wght].ttf`;
  license: `assets/fonts/LibreCaslonText-OFL.txt`.
- `stay-hero.jpg`: the Make export's `photos.lodge` Unsplash URL
  (`photo-1768047845974-a1830dfb186a`).
- `home-invitation.jpg`: the Make export's invitation background URL
  (`photo-1768047846080-d477e260ff00`).
- No fabricated production properties, ratings, reservations, payments or
  operational charts were introduced to imitate the Make preview.

## Validation artifacts and limits

Before this pass, 67 baseline tests passed and one desktop-detail assertion
failed because it expected a bottom action at a width already using an action
rail. The assertion now checks the visible desktop rail; existing mobile detail
tests retain bottom-action coverage. The checkout scrolling test now follows
Scrollable instead of depending on its former ListView implementation.

`test/ui_migration_test.dart` checks home query/category routing, full customer
page layouts at 320/768/1440px, and each existing management sidebar destination
at 390/1440px using the production theme. Running with
`--dart-define=CAPTURE_UI=true` writes rendered previews to
`../migration-backups/previews/`. Fixture users and properties stay in tests.
The changed-file list for this pass is in
`../migration-backups/changed-in-this-pass.txt`; the Git working tree also
contains substantial earlier changes that are not part of this pass.

These screenshots are review artifacts, not pixel-comparison goldens against
original Figma renders. This source-derived migration does not establish
pixel-exact parity across browsers, font rasterizers, text scales or devices.
No Android/iOS/macOS/native Windows release builds or live production provider
transactions have been validated by this UI pass.

## Completed checks

- Full Flutter suite: 80 tests passed (including booking/unlock restrictions,
  listing locations, reviews, rooms, walk-ins, responsive navigation and portal
  separation).
- Final visual/navigation rerun after the last font/spacing refinements:
  12 tests passed, covering the provided customer pages and all existing
  management sidebar destinations at the documented sizes.
- Final static analysis: no issues found.
- Release JavaScript web compilation succeeded. Flutter's Wasm dry run also
  succeeded; no live Wasm deployment is claimed.
- Visually inspected desktop and mobile home, footer, auth, customer, agent,
  admin, property-detail and payment previews. Render captures do not substitute
  for live device/provider testing or original Figma pixel goldens.
- Palette declarations were compared with the pre-edit snapshot and match.

## Files changed in this continuation

New: `docs/UI_MIGRATION.md`, `lib/core/widgets/booking_progress.dart`,
`lib/core/widgets/metric_card.dart`, `lib/core/widgets/portal_scaffold.dart`,
`lib/features/home/presentation/home_sections.dart`, `test/ui_migration_test.dart`,
and the licensed font/decorative image files under `assets/`.

Existing files changed (relative to the pre-edit snapshot):
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/design_tokens.dart`
- `lib/core/widgets/portal_page_header.dart`
- `lib/features/account/presentation/account_screen.dart`
- `lib/features/admin/presentation/admin_dashboard_screen.dart`
- `lib/features/agent_portal/presentation/accommodation_agent_dashboard_screen.dart`
- `lib/features/agent_portal/presentation/agent_dashboard_overview.dart`
- `lib/features/agent_portal/presentation/apartment_agent_dashboard_screen.dart`
- `lib/features/agent_portal/presentation/apartment_availability_tab.dart`
- `lib/features/agent_portal/presentation/rental_agent_dashboard_screen.dart`
- `lib/features/agent_portal/presentation/room_inventory_tab.dart`
- `lib/features/checkout/presentation/checkout_screen.dart`
- `lib/features/financial_management/presentation/financial_management_screen.dart`
- `lib/features/home/presentation/haven_link_shell.dart`
- `lib/features/home/presentation/home_screen.dart`
- `lib/features/properties/presentation/multi_room_stay_screen.dart`
- `lib/features/properties/presentation/widgets/property_card.dart`
- `lib/features/reviews/presentation/admin_reports_tab.dart`
- `lib/features/reviews/presentation/admin_reviews_tab.dart`
- `lib/features/reviews/presentation/agent_reviews_tab.dart`
- `lib/features/search/presentation/property_browse_screen.dart`
- `test/property_detail_test.dart`
- `test/widget_test.dart`
- `pubspec.yaml`
