# lib/ — layout

Feature-based, as the plan's Phase 0 requires and `frontend/CLAUDE.md` details.

| Directory | Holds |
|---|---|
| `core/theme/` | The design tokens (Phase 1): `AppColors`, `AppTypography`, geometry, motion, category accents, and `AppTheme` which assembles the `ThemeData`. Import `app_theme.dart`; reach tokens with `context.colors` / `context.type` / `context.motion`. |
| `core/domain/` | Small domain types more than one feature needs — `VerificationTier`. |
| `core/` (later) | API client, routing, config. No feature may import another feature; they meet here. |
| `features/<feature>/` | One directory per product feature (auth, service_wizard, bookings …), each with `presentation/`, `controller/` (Riverpod) and `data/` layers. `features/gallery/` is the Phase 1 component gallery, reachable at `/gallery`. |
| `shared/` | The shared widgets (Phase 1), one directory per kind — `buttons/`, `cards/`, `badges/`, `chips/`, `inputs/`, `toggles/`, `rating/`, `navigation/`, `headers/`, `avatar/`, `states/`, `sheets/`, `feedback/`, `motion/`. Import them all through `shared/shared.dart`. |
| `app.dart` | The root widget: the themed `MaterialApp` and the route table. |
| `main.dart` | Entry point only — bootstraps and calls `runApp`. |

Each later phase adds its own feature directory and nothing else. A widget that a second feature needs moves to `shared/`; it is not copied.
