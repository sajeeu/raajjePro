# Session 9 corrections — two links, and a file the project is missing

This is the cleanest session yet on the things that usually break. Legal is placeholder-marked exactly right — banner, hatched bars, `[ placeholder — pending legal review ]`, and only the marketplace sentence written as real text. Delete account has no rejected state and states all four facts. The only toggles are marketing and the weekly digest, under a line that says booking updates have no switch. The current device offers *Sign out*, not *Revoke*. Change phone reads "Shown as you enter it, like registration" — no check mark anywhere. The island picker carries **"Placeholder islands — the real island list is pending."** And the FAQ demo answers use Pest Control and Appliance Repair, which is Round 25 landing in new work without being asked for.

Two navigation fixes, and one thing that isn't yours to fix.

---

## 1. The role switcher doesn't switch

`Profile.dc.html`'s **Provider** row in the sheet calls `switchProvider`, which shows a toast:

> Opens Become a Provider — first-listing setup

The copy is right. But this is the one action the entire sheet exists to perform, and it goes nowhere — while **`Become a Provider.dc.html` is a real sibling artboard** that has existed since Round 21 (see below for why you may not see it). Make it a link:

```
href="./Become%20a%20Provider.dc.html"
```

Keep the explanatory panel underneath exactly as written — the first-switch / already-set-up / instant-and-reversible trio is correct and well phrased.

## 2. Profile's "Saved" row lands on Explore

The row is labelled **Saved · 7 saved services** but points at `./Discovery.dc.html`, whose default scenario is Explore — so tapping "Saved" shows the category grid. Saved lives inside that same artboard as its `Saved` screen state.

If the canvas can't deep-link a scenario, leave the href and change the subtitle to something honest about where it goes, or point it at the Saved state if your linking supports it. What it must not do is promise Saved and show Explore.

---

## Not a correction — a project-hygiene note for whoever owns the canvas

**`Become a Provider.dc.html` is missing from the design project.** It exists in the repo, reviewed and committed since Round 21, and the redesign plan lists it in the status table. It is simply not among the project's files, which is presumably why the switch became a toast rather than a link.

Nothing to do inside this session — but it will bite session 11 (provider dashboard), which needs to link to it and inherit from it. Worth re-uploading it to the project before that session starts.

---

## Leave alone

Everything else across all six artboards. Specifically: every word of Legal's placeholder treatment; the delete flow end to end including the type-DELETE gate and the frozen confirmation; the sessions list and its per-device revoke semantics; download-my-data's contents list and email destination; the marketing/digest toggles and the always-sent line; Saved Preferences' address sheet, island note, time-window chips and standing-instructions editor; Notifications' "Ibrahim Rasheed confirmed receipt" and its `Nothing new.` empty state; and Help & Support's tracked-case reference, the support/feedback split, and the line that app feedback never reaches a provider's profile.

Two small things I am deliberately **not** asking you to change, noted so nobody 'fixes' them later: Saved Preferences offers four placeholder islands where the plan's convention is six — the note matters more than the count — and Account Settings' "2 devices signed in" subtitle doesn't recount after a revoke, which is demo-state bookkeeping, not design.
