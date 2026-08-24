Round 23 landed correctly and the writing is good — the urgent entry's "your request goes to every qualified provider nearby, you choose from up to three offers" is exactly the honest framing, and the rebuilt empty state naming `Under MVR 300` and `Hulhumalé` as the pair that collide is better than what it replaced. Keep all of it.

Two corrections. The first undoes the point of the change.

## 1 — The emergency entry is below the category grid

It currently sits **after** the twelve categories, inside the scrolling area. So a customer with water spreading has to scroll past the full grid to find it.

That is the opposite of what Round 23 was for. The marker was removed from cards precisely because **someone in an emergency is not browsing** — and the replacement then landed somewhere you can only reach by browsing.

**Move it directly beneath the search field**, above the category grid, and keep it out of the scrolled content so it is visible the moment Explore opens. Everything else about it — the wording, the red treatment, the arrow — is right and should not change.

While it moves, check the same thing on Home: the emergency entry has to be reachable without scrolling there too.

## 2 — The card photos are hotlinked from Unsplash

Every entry in `SVCS` carries a `https://images.unsplash.com/...` URL.

Three problems, in order of how soon they bite:

- **They will not render outside the editor.** A published page blocks every external host except Google Fonts, so the cards fall back to the category icon anywhere the prototype is shared or exported.
- **They rot.** A remote URL is a dependency on someone else's server, in a file that is meant to be the durable reference for how this screen looks.
- **They are someone else's photographs**, in a file that will be handed to developers building a commercial product.

`Home.dc.html` already solved this — it uses uploaded image slots (`cleaning.jpeg`, `plumbing.jpeg`, `electrical.jpeg`, `beauty.jpeg`, `photography.jpeg`) rather than hotlinking. **Use the same mechanism here**, reusing those five uploads across the eleven sample listings by category. Where a category has no uploaded photo, pass no photo at all and let `ServiceCard` fall back to its category icon — that fallback exists and looks correct.

## Everything else stays

The four screens, sort, sponsored ordering, filters, island sheet, states, rollback, and the component boundaries. This is a move and a swap.
