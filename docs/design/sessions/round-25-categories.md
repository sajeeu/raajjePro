# Round 25 — two categories changed; three artboards carry the old ones

A plan revision (Round 25, revision 5.11) changed the twelve categories: **Gardening is replaced by Pest Control**, and **Computer is renamed Appliance Repair** (broadened to household appliances — washing machines, refrigerators, ovens, TVs — alongside the computer and phone repair it already covered). Booking modes, windows, and everything else about both slots are unchanged: request-based, not emergency-capable.

Three artboards render the old names. This is a data correction, not a redesign — same tiles, same cards, same layout.

---

## Discovery.dc.html

- **Category grid:** the `Gardening` tile becomes **`Pest Control`** and the `Computer` tile becomes **`Appliance Repair`**, each with a fitting icon (bug/shield-style for Pest Control; washing machine or wrench-on-appliance for Appliance Repair — your call, consistent with the grid's icon weight). Same positions, still twelve, still 3×4.
- **Sample data:** Adam Naseer's `Gardening` listing becomes a Pest Control one — e.g. *"Home Pest Treatment"*, category `Pest Control`, same tier/rating/price shape as now.

## Home.dc.html

- The `Tech Solutions` sample listing's category becomes **`Appliance Repair`** (both places it appears). If its title says computer repair, a title like *"Appliance & Computer Repair"* keeps the demo honest.
- Adam Naseer's `Gardening` sample becomes the same Pest Control listing as on Discovery.
- If the category rail/grid on Home names either old category, same tile swap as Discovery.

## ServiceCard.dc.html

- The `category` prop's enum options: replace `Gardening` → `Pest Control` and `Computer` → `Appliance Repair`. Nothing else on the component changes.

## Leave alone

Everything else, everywhere. No other artboard names either category. Booking demo data (cleaning, plumbing, photography) is untouched. The wizard's step-1 grid isn't built yet — session 10 will inherit the new twelve from the brief.
