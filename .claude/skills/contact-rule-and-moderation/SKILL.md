---
name: contact-rule-and-moderation
description: Use when working on messaging, the enquiry channel, contact-pattern detection, the emergency contact reveal, blocking, reports, or the moderation queue. Triggers on mentions of chat, message, enquiry, contact, block, report, or moderation.
---
# The Contact Rule & Moderation

Renamed from "contact-gating" in v4 — gating described a mechanism that no longer exists. There is no unlock schedule, no per-status visibility ladder.

THE RULE: phone numbers are never exchanged between customer and provider, with EXACTLY ONE exception — `POST /v1/bookings/:id/reveal-contact`, emergency bookings only, validating all seven request-time conditions server-side (the Phase 10b kill switch is a separate runtime check, not one of the seven): emergency mode; `accepted` or later; customer-initiated; mutual and simultaneous; counterparty notified; expiring 24 hours after terminal state; logged. Also kill-switchable at runtime.

`GET /v1/bookings/:id/contact-info` DOES NOT EXIST. Do not create it. It was a far broader mechanism exposing a number on every booking type with no conditions, and it was deleted. WhatsApp and Viber handles are not collected anywhere and cannot be revealed by anything.

CHAT IS THE SOLE COORDINATION CHANNEL for a booking's life. It opens at `quote_offered` for request-based and at `accepted` for slot and emergency. ROUND 27: it stays open for 7 days after completion (the callback-guarantee window), THEN LOCKS READ-ONLY — history never deleted, dispute reopens it, Book Again and the callback claim's linked booking carry anything later. "Never torn down" is pre-Round-27 and stale.

CONTACT-PATTERN DETECTION IS SILENT AND LOGGED — never a block, never a redaction, and never shown to the sender. Round 12 removed the user-visible nudge outright: no banner, no reminder, nothing near the composer. The message always sends. Maldivian mobiles are 7 digits beginning 7 or 9; AC serials are 7–15 digit strings — not reliably distinguishable, and blocking that content defeats the enquiry channel's purpose. Photos are allowed anyway, so a business-card photo passes a text filter regardless. Detections aggregate to a PROVIDER-LEVEL signal ("tripped detection in 40 of 52 enquiries"), never per-message noise.

BLOCK IS TWO ACTIONS: "Mute this conversation" (one thread) and "Block this person" (account-level — no messaging and no new bookings either way, enforced server-side at conversation-creation AND booking-creation). A BLOCK NEVER SEVERS A LIVE BOOKING'S CHAT: it applies to future bookings and messages, while the existing booking's thread stays open until terminal state with a notice explaining why. Killing it mid-job would leave a scheduled visit uncoordinated.

Separately, a provider may DECLINE FUTURE BOOKINGS from a specific customer — self-service, enforced at booking creation, independent of the Report path, one-directional, and it does not silence the existing conversation.

MODERATION ACTIONING HIDES, NEVER DELETES. Hidden content stays visible to its OWNER, who sees the category and reason and can appeal. Everyone else cannot find it.
