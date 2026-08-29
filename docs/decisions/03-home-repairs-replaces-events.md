# Round 26 — Home Repairs replaces Events

**Status: adopted as Round 26 (2026-08-27). Plan revision 5.12.**

## The decision

**Events is removed from the twelve categories and replaced by Home Repairs** — small household jobs: partial painting, tile replacement, mounting and hanging, sealing and grouting, furniture assembly, door and lock fixes, minor carpentry.

The name was chosen over three alternatives:

- **Handyman** — the most recognized term for the work, but it would be the only category naming a person rather than a service, and it is gendered. Every other category names the work (Cleaning, not Cleaner).
- **Home Maintenance** — reads preventive and contract-flavored rather than fix-this-tile.
- **Odd Jobs** — the plainest description, but informal and weak as a search term.

**Home Repairs** completes a natural triple with AC Repair and Appliance Repair: climate · devices · the fabric of the home. The boundary with Appliance Repair is stated in the seed description — Appliance Repair is devices; Home Repairs is walls, tiles, doors and fittings.

## Configuration

This is a replacement, not a rename. The two categories are configuration opposites, and Home Repairs inherits nothing:

| Field | Events (removed) | Home Repairs |
|---|---|---|
| `bookingMode` | request | request |
| `quoteExpiryMinutes` / `quoteApprovalMinutes` | 1440 / 4320 | **120 / 240** — a cracked tile is closer to a blocked drain than to a wedding |
| `minimumLeadTimeMinutes` | 2880 (the system's ceiling) | **180** — same as Cleaning and Pest Control: home visits where the provider brings materials |
| `emergencyCapable` | false | false |
| `occasionPresets` | Wedding, Birthday, … | **null** — occasion chips are now Photography and Boat Charter only |

Consequences worth noting:

- The **2880-minute lead ceiling leaves the system** — the longest lead is now 1440 (Photography, Moving, Boat Charter).
- The **long quote group shrinks to three**: Photography, Moving, Boat Charter.
- §Phase 9's step-1 guidance for activity categories ("name the specific offering") now covers Photography and Boat Charter only.
- Wizard tag chips for Home Repairs: Painting · Tiling · Mounting & hanging · Furniture assembly · Door & lock fixes · Sealing & grouting.
- Photography keeps event work via its tags — the bare tag `Events` renames to `Event coverage` so the retired category name appears nowhere.

## Enforcement

`verify-dc.py` gains a locked rule banning `'Events'` / `>Events<` / `&quot;Events&quot;` in prototypes, alongside the Round 25 rule. Four prototypes carry the retired category (`Home`, `Discovery`, `Create Service`, `ServiceCard`) and fail the gate until the Round 26 correction round lands in the design project and is re-imported — tracked in `docs/design/sessions/round-26-home-repairs.md`.

Session 12's casting decision ("Boat Charter or Events") resolves to **Boat Charter**.
