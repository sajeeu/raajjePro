# lib/ — layout

Feature-based, as the plan's Phase 0 requires and `frontend/CLAUDE.md` details.

| Directory | Holds |
|---|---|
| `core/` | Cross-cutting concerns: theme tokens, API client, routing, config. No feature may import another feature; they meet here. |
| `features/<feature>/` | One directory per product feature (auth, service_wizard, bookings …), each with `presentation/`, `controller/` (Riverpod) and `data/` layers. |
| `shared/` | Widgets used by more than one feature: buttons, cards, badges, empty states. Phase 1 fills this. |
| `app.dart` | The root widget. |
| `main.dart` | Entry point only — bootstraps and calls `runApp`. |

Phase 0 leaves `core/`, `features/` and `shared/` empty on purpose. Phase 1 adds the design system; each later phase adds its own feature directory and nothing else.
