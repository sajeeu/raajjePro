# lib/ — layout

Feature-based, as the plan's Phase 0 requires and `frontend/CLAUDE.md` details.

| Directory | Holds |
|---|---|
| `core/theme/` | The design tokens (Phase 1): `AppColors`, `AppTypography`, geometry, motion, category accents, and `AppTheme` which assembles the `ThemeData`. Import `app_theme.dart`; reach tokens with `context.colors` / `context.type` / `context.motion`. |
| `core/domain/` | Small domain types more than one feature needs — `VerificationTier`. |
| `core/api/` | Phase 3's one HTTP path to the backend: `ApiClient`/`HttpApiClient`, the envelope decode, `ApiException`/`ApiNetworkException`, and the single-flight `ACCESS_TOKEN_EXPIRED` refresh-and-retry. Every feature's data layer goes through this, never `http` directly. |
| `core/auth/` | `AuthController` and the one `AuthState` the root widget switches on (`AuthUnknown`/`AuthGuest`/`AuthSessionExpired`/`AuthSignedIn`); `AuthApi` (the typed `/v1/auth` and `/v1/users/me` calls); `TokenStore` (secure storage); `FormDraftStore` (in-memory, the Session Expired promise's mechanism); `auth_models.dart` (`UserAccount`, `PhoneNumber`, `RegisterRequest`, …). |
| `core/crash/` | `CrashReporter` interface, pulled forward from Phase 21 — Sentry behind it, a no-op with no `SENTRY_DSN`. |
| `core/clock.dart` | `clockProvider`, overridable in tests so a fixed `DateTime` drives OTP/rate-limit countdowns without a real `Duration` wait. |
| `core/format/` | Small display helpers shared across features — `relative_time.dart`'s `shortDate`. |
| `core/` (later) | Routing, config. No feature may import another feature; they meet here. |
| `features/<feature>/` | One directory per product feature (auth, account, service_wizard, bookings …), each with `presentation/`, `controller/` (Riverpod) and `data/` layers. `features/gallery/` is the Phase 1 component gallery, reachable at `/gallery`. |
| `features/auth/` | Sign In, Register, Verify Email (email OTP, shared by verify-email and change-email via `OtpPurpose`), Session expired. Widgets: `PhoneField`, `OtpCodeEntry`, `InlineNotice`, `CountdownText`, `AuthHero`, `RoleToggle`, `SocialSignInRow`. |
| `features/account/` | Account settings and its sub-screens: Active sessions, Download my data, Delete account, Change password, Change email, Change phone. `AccountController`/`ChangeFormController` (Riverpod), `SettingsRow`. |
| `features/legal/` | `LegalPlaceholderScreen` — Terms of Service / Privacy Policy placeholders with no policy prose (root CLAUDE.md invariant 1d); Phase 23 replaces them with real, legally-reviewed copy. |
| `shared/` | The shared widgets (Phase 1), one directory per kind — `buttons/`, `cards/`, `badges/`, `chips/`, `inputs/`, `toggles/`, `rating/`, `navigation/`, `headers/`, `avatar/`, `states/`, `sheets/`, `feedback/`, `motion/`. Import them all through `shared/shared.dart`. |
| `app.dart` | The root widget: the themed `MaterialApp` and the route table. |
| `main.dart` | Entry point only — bootstraps and calls `runApp`. |

Each later phase adds its own feature directory and nothing else. A widget that a second feature needs moves to `shared/`; it is not copied.
