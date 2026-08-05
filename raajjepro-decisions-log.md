# RaajjePro — Consolidated Design Decisions

Based on the adversarial design review + 48 decision questions, resolved 2026-08-03.

## Section 1: Core Booking & Transactional Flow

**1.1 / 1.8 — Booking lifecycle with time-slot blocking**
- ✅ **Adopt:** Provider publishes available time slots; customer books a slot → slot is immediately unavailable to others (prevents double-booking by design).
- **Flow:** customer selects slot → booking created as `requested`, slot marked reserved → provider gets in-app accept prompt (no contact/chat, no external notification allowed until accepted) → provider accepts/declines via in-app only → if accepted, customer is prompted to pay → customer confirms payment → provider confirms receipt → booking moves to `confirmed`, contact info unlocks.
- **Added amount requirement:** every Booking carries `agreedAmount` set at provider acceptance.
- **Timeout:** 7 days in `payment_claimed` before auto-completing.
- **Database constraint:** unique (providerId, listingId, scheduledFor) prevents any double-booking at the DB level, application cannot override.

**1.2 — Booking amount field**
- ✅ **Adopt recommendation:** add `agreedAmount` to Booking; both payment-claimed and confirm-receipt actions reference it explicitly in UI copy.

**1.3 — Dispute path**
- ✅ **Adopt recommendation:** add `disputed → disputed_resolved` transition, admin-actionable. Add customer-initiated dispute path symmetric with provider's.
- **Late dispute:** if provider disputes after booking is completed, accept the dispute, add to moderation queue; booking stays completed.

**1.4 — Review eligibility decoupled from provider completion**
- ✅ **Adopt recommendation:** review becomes postable when booking reaches `confirmed`, not `completed`. Provider no longer gates review access.

**1.5 — Trial completion trigger**
- ✅ **Drop:** remove the "3rd completed booking" trial-end trigger. Trial ends only on day 60, preventing perverse incentives.

**1.6 — Trial clock starts at first booking received**
- ✅ **Adopt recommendation:** trial begins when a provider's first booking is confirmed (not when listing is published). Demonstrates value before asking for money.

**1.7 — lifecycleStatus derived from published-listing count**
- ✅ **Adopt recommendation:** derive public visibility from `count(published listings) > 0` rather than a stored `lifecycleStatus` field. Stored field can drift; live count is source of truth.

**1.9 — Accepting New Customers flag**
- ✅ **Fix:** move from per-listing to per-provider toggle. Billing pause logic and messaging all key off provider-level only.

**1.10 — Boost naming**
- ✅ **Fix:** rename `search_boost` ad placement type to `search_sponsored_listing` to avoid collision with `boosted_placement` entitlement.

**1.11 — Draft idempotency**
- ✅ **Fix:** `POST /v1/listings` with idempotency key; client provides key; server returns same result on repeat calls. Prevents orphan drafts on connection retry.

---

## Section 2: Product Design

**2.1 — Provider workspace navigation**
- ✅ **Adopt:** add role switcher (customer/provider mode); promote My Services Dashboard to primary-nav or a clear provider-tab position; don't bury it under Profile.

**2.2 — Cold-start Home**
- ✅ **Adopt:** launch-mode Home that collapses to 2 sections + category grid until catalogue-size threshold (e.g., 200+ listings). Unlock full 9-section layout on threshold.

**2.3 — Offline/poor-network handling**
- ✅ **Adopt:** queue writes on disconnect; retry on reconnect; disallow step navigation in wizard until current step's PATCH succeeds. Builds resilience into the highest-friction flow.

**2.4 — Accessibility**
- ✅ **Now, in Phase 1:** add a11y acceptance criteria to `030-design-system.mdc` before any screen is built. Minimum touch targets (48dp), contrast ratios (WCAG AA), `Semantics` labels, `textScaler` support, and reduced-motion overrides for all motion.

**2.5 — Wizard framing**
- ✅ **Show required-fields-remaining:** replace or supplement step-of-7 with "N required fields left to publish." Reduces perceived commitment.

---

## Section 3: Feature Gaps

| Gap | Decision |
|---|---|
| Account deletion | ✅ Add to Phase 3. App Store blocker. |
| Double-booking prevention | ✅ Solved by slot-blocking design. |
| Block user | ✅ Add to Phase 18 (Messaging). |
| Report from chat | ✅ Add to Phase 18. Allow reporting within a conversation. |
| Provider analytics | ✅ Define as dashboard (views/bookings/ratings per listing, weekly digest email). Sell with subscription. Add weekly digest to Phase 19. |
| Booking reschedule | ✅ Add to Phase 17. Allow rebooking a different slot for confirmed bookings. |
| In-app password/email/phone change | ✅ Add sub-screens to Phase 6 (Profile). |
| Session/device management | ✅ Add to Phase 6. Allow users to see active sessions, revoke old ones. |
| Deep links / web fallback | ✅ Add to Phase 16. Listings, providers, and bookings resolve via web URL with a minimal fallback page. Required for share feature and SEO. |
| Receipts / invoices | ✅ Downloadable PDF invoice on payment confirmation. Add to Phase 10a. |
| Entitlement reversal | ✅ Add admin endpoint to reverse a payment confirmation. Hard rule: never delete credits, only refund. |
| Admin provisioning | ✅ Add to Phase 2. Minimal user/role creation, no MFA in v1, but required to bootstrap. |
| Data export | ✅ `GET /v1/users/me/data-export` in Phase 3. Returns user's own data as JSON. |
| Referral program | ✅ Add to Phase 16. "Share and earn MVR 50 credit for each booking referral." |

---

## Section 4: Technical Architecture

**4.1 — Wallet concurrency & idempotency**
- ✅ **Money field type:** integer laari (MVR × 100) throughout. Add to `010-backend-conventions.mdc`.
- ✅ **Wallet race:** transaction + DB-level `CHECK (balance >= 0)` constraint. No check-then-act.
- ✅ **Idempotency:** client provides idempotency key for every money-adjacent POST. Server deduplicates via unique (userId, operationType, key). Add to API contract.

**4.2 — Payment proof access control**
- ✅ **Adopt:** private objects + unrestricted admin read (no time limit). Separate bucket/prefix from listing media. EXIF stripping on upload.

**4.3 — Background job runner**
- ✅ **Add to Phase 0 / Phase 2:** PostgreSQL pg_cron or equivalent. Seed 3 jobs: trial-expiry check, ad-campaign expiry, event log rollup.

**4.5 — Counter design consistency**
- ✅ **Fix:** one event log (`ListingViewEvent`, `BookingEvent`, etc.), periodic rollup to the Listing aggregate fields. No hand-maintained counters on hot paths.

**4.6 — Deletion semantics**
- ✅ **Soft-delete via visibility flag.** Listings, reviews, messages, users all have `status` or `visibility` field (`active`/`hidden`/`deleted`). Never hard-delete. Add soft-delete cascade rules to Phase 2.
- ✅ **Account deletion:** anonymize all authored content (reviews, listings, messages). Replace name/email/phone with placeholder. Preserve content and ratings.

**4.7 — Entitlement enforcement at publish**
- ✅ **Add check:** `POST /v1/listings/:id/publish` now calls `getProviderEntitlements` and verifies they're not over-cap before publishing (previously only checked at draft creation).

**4.8 — ID scheme**
- ✅ **Adopt:** UUIDs for all entities. No enumeration surface. Update `010-backend-conventions.mdc`.

---

## Section 5: Security

**5.1 — Admin authentication**
- ✅ **Add to Phase 2:** real admin identity model. Roles: `payment_admin`, `moderation_admin`, `admin`. Single role (`admin`) acceptable for v1 (simpler). MFA deferred post-v1. Network segregation deferred post-v1.
- ✅ **Audit trail:** every admin action logged with admin ID, timestamp, action type, target, reason. Queryable.

**5.2 — Output encoding for admin web app**
- ✅ **Add to Phase 10a:** Content Security Policy header, output encoding on all user-authored text (listing descriptions, reviews, comments).

**5.3 — OTP rate limiting**
- ✅ **Add to Phase 3:** rate-limit OTP sends to 3 per phone number per 15 minutes. Add to global rate-limit rules.

**5.4 — SMS provider**
- ✅ **Pin decision before Phase 3:** choose a provider (Twilio, AWS SNS, etc.) with a cost model and delivery-failure fallback. Document SMS lead times (sender-ID registration, etc.).

---

## Section 6: Business & Monetization

**6.1 — Monetization sequencing**
- ✅ **Adopt:** defer Phase 8b (credits) and 8c (advertising) entirely past v1. Rebuild Phase 8a as subscription-only (simple model, simple admin). Recover ~20% of build effort.
- ✅ **Referral bonus:** add to v1 (Phase 16): "earn MVR 50 credit for each booking-generating referral."

**6.2 — Trial timing and value**
- ✅ **Adopt:** trial starts at first booking received, not first publish. Guarantees value demonstrated before asking for money.

**6.3 — Subscription + badge = verified**
- ✅ **Adopt:** badge requires BOTH identity verification (Phase 23, background check) AND active premium subscription. If subscription lapses, badge is hidden.

**6.4 — Manual payment automation**
- ✅ **Add to Phase 10a:** bank-statement CSV import with reference-code auto-matching. Reduce manual confirmation overhead.
- ✅ **Payment confirmation SLA:** admin must confirm/reject within 48 hours. Set as policy, not code, but document for support.

**6.5 — Trial expiry behavior**
- ✅ **7-day grace + warning:** send notification 7 days before trial end; on expiry, downgrade to free tier (hide over-cap listings, disable badge/analytics). Reversible on any payment.
- ✅ **Pause logic:** provider can pause billing max 10 days; after 10 days, paused time is "spent" and trial restarts from zero (if not yet completed). Prevent indefinite free rides.

---

## Section 7: Booking Payment Attestation

**7.1 — Booking status machine (revised with slot-blocking)**
```
Time slot exists: requested (after customer accepts and pays) → 
provider accepts in-app (no contact/chat) →
customer shown payment details, pays externally →
customer taps "I've Paid" → payment_claimed →
provider confirms receipt (or disputes) → confirmed (or disputed) →
provider marks complete → completed →
customer can now review
```

**7.2 — Payment attestation**
- ✅ **Two-sided self-attestation only.** Never imply verification. Copy: "Provider confirmed receipt" not "Payment Verified."
- ✅ **7-day grace:** if provider doesn't confirm/dispute within 7 days of customer claiming payment, auto-complete the booking.
- ✅ **Disputed outcome:** add to moderation queue, not auto-resolved. Customer and provider sort via admin help.

**7.3 — Contact visibility**
- ✅ **Symmetric gating:** neither side sees the other's phone/WhatsApp/Viber until booking reaches `confirmed`. Unlock at accept is not enough; unlock only at confirmed (after payment attestation).

---

## Section 8: Notifications & Real-Time

**8.1 — Push notifications**
- ✅ **Push required and default-on; cannot opt out.** Email and in-app inbox are opt-in. Critical for provider booking acceptance.
- ✅ **Add to Phase 19:** notification types for payment events (submission_confirmed, submission_rejected), booking events, messaging, reviews.

**8.2 — Notification rules**
- ✅ **Cannot disable push** (provider acceptance is load-bearing). Email/in-app are optional.
- ✅ **Add digest:** weekly email for providers (views, bookings, reviews, top listings). Add to Phase 19.

---

## Section 9: Money & Payments

**9.1 — Booking with quote pricing**
- ✅ **Adopt:** request + await quote + approve quote + accept offer + pay flow. Add as a separate booking-status path in Phase 17.

**9.2 — Subscription pause**
- ✅ **Adopt:** provider can pause billing at any point. After 10 days paused, pause expires and trial restarts (if trial not yet completed). No auto-suspend, no grace period beyond the pause window itself.

**9.3 — Payment rejection retry**
- ✅ **Adopt:** immediate retry allowed. Provider sees rejection reason and can resubmit new proof right away.

**9.4 — Payment appeals**
- ✅ **Adopt:** appeal + re-open workflow. Provider sees rejection reason, can request admin re-review or resubmit.

**9.5 — Invoices**
- ✅ **Downloadable PDF invoice** on every payment (subscription, referral bonus, one-time purchases). Add to Phase 10a.

**9.6 — Money expiry**
- ✅ **No expiry:** subscription stops charging when cancelled; credits never expire; advertiser-purchased time expires by design only (start/end date).

**9.7 — Ad scheduling**
- ✅ **Future-dated campaigns:** providers can schedule ads to begin on a future date. Allows planning.

---

## Section 10: Admin & Moderation

**10.1 — Admin roles**
- ✅ **Single 'admin' role in v1** (simplest). All admins can confirm payments, hide content, suspend providers. Separate roles deferred post-v1.

**10.2 — Payment confirmation workflow**
- ✅ **Single admin review** (no 4-eyes in v1). Any admin can confirm/reject. Simpler, faster.

**10.3 — Moderation transparency**
- ✅ **Yes, with category + reason.** Hidden content shows user the reason ('inappropriate content', 'spam', 'misleading pricing', etc.) and an appeal link.

**10.4 — Hidden reported listing visibility**
- ✅ **Hidden from everyone except owner.** Owner can still see it, edit, or appeal; public cannot find it.

---

## Section 11: Reviews & Trust

**11.1 — Review eligibility**
- ✅ **Only after completed booking.** Prevents fake reviews. One review per completed booking.

**11.2 — Verified badge logic**
- ✅ **Badge requires identity verification AND active premium subscription.** If subscription lapses, badge is hidden (but identity verification remains).

**11.3 — Response time visibility**
- ✅ **Public metric.** Calculate from booking/message-acceptance history. Display in provider profile and listings as a trust signal.

**11.4 — Search ranking**
- ✅ **No visibility difference** between verified and unverified providers in baseline search. Verification improves badge/placement but not findability.

---

## Section 12: Messaging

**12.1 — Scope**
- ✅ **Booking-specific only.** Conversations can only exist for active bookings. Customers cannot message providers pre-booking; reduces spam, simplifies moderation.

**12.2 — Phone verification**
- ✅ **Required for both messaging and booking** (existing rule, confirmed).

---

## Section 13: Pricing & Rates

**13.1 — Variable pricing**
- ✅ **Per-listing pricing.** Each listing can have its own hourly/daily/fixed rate. More flexibility; adds complexity to wizard but essential for realistic service pricing.

**13.2 — Cancellation**
- ✅ **Cancelled booking slots become available.** Slot is freed when customer cancels; provider can choose to re-offer or keep it blocked.
- ✅ **Provider cancellation:** cancel anytime, no penalty. Tracked but not punished; avoids forcing unwilling providers.

---

## Section 14: Messaging & Notifications – Additional Clarity

**Note on contact-info in booking flow:**
- Before accepted: no contact info shown to either party.
- After accepted, before payment-claimed: provider sees customer name only (via booking context), not direct phone.
- After confirmed: both parties see each other's phone/WhatsApp/Viber via the contact-info endpoint only. This is the unlock moment.

---

## Summary of Major Changes from Original Plan

1. **Booking lifecycle reordered** with slot-blocking to prevent double-booking and match real transaction flow (provider accepts before payment).
2. **Trial starts at first booking received**, not first publish, ensuring value is demonstrated.
3. **Monetization deferred:** Phase 8b (credits) and 8c (ads) cut from v1; rebuild Phase 8a subscription-only.
4. **Accessibility required from Phase 1**, not retrofitted.
5. **Soft-delete everywhere:** no hard deletes, all content reversible.
6. **Admin authentication real but minimal** in v1 (role check + audit log, no MFA/network separation).
7. **Referral program added** for viral growth.
8. **Payment proof storage separated** from listing media; no enumeration via UUID; rate-limiting on OTP and APIs.
9. **Cold-start Home** designed to look intentional at launch.
10. **Grace period + warning** on trial expiry (7 days notice, then downgrade to free tier).
11. **Contact gating symmetric:** neither party sees phone until confirmed.
12. **Notifications** are push-required (default-on, cannot disable); email/in-app opt-in.

