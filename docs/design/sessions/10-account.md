Build the account surface: **Profile**, the **role switcher**, **Account settings** (with active sessions, download my data, and delete account), **Saved preferences**, **Notifications**, **Help & support**, and **Legal**.

**Attach:** `Profile_customer.jpg` — audited clean, so Profile is fidelity work. Everything else has no mockup: propose the design, inheriting the established vocabulary (session 8's form and list idioms are the nearest relatives).

**Import the components**: `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` (`active="Profile"`) · `SkeletonCard` · `EmptyState`. Cast as established: Aishath Nazim is the signed-in customer.

Suggested artboards — your call on the split:

- `Profile` — the mockup screen, plus the **role switcher as a sheet** over it
- `Account Settings` — one artboard, scenarios for the list · active sessions · download data · the delete flow
- `Saved Preferences`
- `Notifications`
- `Help Support`
- `Legal` — the index plus one open document as the placeholder pattern

---

## The rules that shape this session

**Booking notifications have no off switch, and the screen must not apologise for it.** They are transactional and always sent; the app offers no toggle for them. Marketing and the weekly digest are opt-in and separate — those two get switches. Any state that renders a toggle against booking notifications is a defect. Be honest about the boundary the product can't cross: the OS can still revoke notification permission, and email is what covers that — but this screen doesn't need to explain OS internals, it just must never promise "you will always get a push."

**Delete account is queued, never refused.** The words carry the design: the request is **accepted immediately**, even with bookings open; the account freezes at once (no new bookings, no new listings, hidden from search); deletion completes when open bookings finish and **within 30 days regardless**; reviews stay with the name removed; identity documents are deleted outright, not anonymised. The confirm action is deliberately hard to hit by accident — but the flow never says "you can't delete because…". There is no such state.

**Phone and email change each re-verify — and the phone still never gets a check mark.** Change email sends a code to the new address (the session-8 verify pattern). Change phone collects the new number and shows it as user-supplied text, exactly like registration. No state may render a phone as verified.

**Legal is placeholder by design.** Four rows — Terms of Service · Privacy Policy · Provider Agreement · Trust & Safety — each opening a readable scrolling document with a last-updated date, and the body text **visibly marked as placeholder** ("Placeholder — legal text pending review" as a banner or watermark pattern, structurally real headings beneath). Never write text that could pass as final policy. The one line of real content: Trust & Safety conveys that RaajjePro is a **marketplace, not the supplier of the work**.

**The island list is still placeholder.** Saved addresses carry an island (`Home · Malé`, `Office · Hulhumalé`). Any island picker this session renders uses a handful of placeholder islands **with a visible note that the real list is pending** — the constraint session 8 tripped over. Don't present a hardcoded eight as though they were the seed.

## Screen notes

**Profile.** Match the mockup: name, photo, member since Jan 2026, saved 7 · bookings 12, rows to My bookings · Saved · Saved preferences · Account settings · Help & support · Legal, a route into provider mode, sign out. Rows link to the real artboards where they exist (`My Bookings`, Discovery's Saved screen).

**Role switcher.** Two named modes, current one evident. Three facts in the copy: first-time switch opens **Become a Provider** (link the artboard — it exists), an already-set-up provider goes straight to My Services, and switching is instant and reversible with nothing lost. Don't invent a provider dashboard preview; My Services is session 11.

**Account settings.** Rows: Change password · Change email · Change phone · Active sessions · Saved preferences · Download my data · Delete account. Active sessions: one row per device — device name, last-used age, current-device marker, revoke per device (`iPhone 14 · Malé · active now` / `Pixel 7 · 3 days ago`) — and revoking one device signs out only that device. Download my data: say what it contains (profile, bookings, reviews, messages) and that it arrives as a file to the account's email. Delete: the copy above, a type-to-confirm or hold-to-confirm, then a frozen-state confirmation restating the timeline.

**Saved preferences.** Saved addresses (label + island), preferred time windows, standing instructions free text (`Gate code 4471. Please call from the lobby.`). Add, edit, remove for each. The fact worth a quiet line: these pre-fill every booking and stay editable there — this screen is why a repeat booking is one screen.

**Notifications.** Unread count 3; entries with event, detail, age (`Booking accepted — Home Deep Cleaning · Mariyam Shifa — 2h`, `Payment confirmed — Ibrahim Rasheed confirmed receipt — 1d`, `New message — Ibrahim Rasheed — 1d`). Unread visibly distinct. Empty state: `Nothing new.` Note the second entry's wording — **"confirmed receipt"**, never "Payment verified."

**Help & support.** Searchable FAQ; a contact form (subject, message, attach a screenshot) whose submission becomes a **tracked case with a reference** — not an email into a void; and a **product feedback** entry clearly labelled as feedback about RaajjePro, with the fact stated that app feedback never appears on any provider's profile.

**Legal.** The index and one opened document demonstrating the placeholder pattern.

## States and combinations

Every screen: populated, loading, error; empty where a list can be empty (notifications, saved preferences, sessions can't be empty — the current device is always there). Watch:

- Delete-account has no rejected state. Its states are: confirm → frozen confirmation. Nothing else.
- The current session's row carries no revoke action against itself (or it's labelled as sign-out) — a device can't revoke the session it's using and keep browsing.
- Change-phone flows never end in a success state that shows a check mark on the number.
- Marketing/digest toggles are the only toggles on Notifications-related settings.

## Guardrails carried forward

- No phone numbers rendered anywhere; no "Payment Verified" language; no editorial labels.
- Categories are the Round 25 twelve — if any category name appears (saved preferences demo data, FAQ examples), it's Pest Control and Appliance Repair, never Gardening or Computer.
- Photos and icons uploaded, never hotlinked. Money as MVR. Emergency stays out of this session.
- No fabricated legal or policy text, anywhere, in any state.
