---
name: admin-panel-conventions
description: Use when working on the admin panel. Triggers on work in the admin web app, or mentions of admin queue, moderation queue, verification queue, audit log, or kill switch.
---
# Admin Panel Conventions

THE ADMIN PANEL IS A SEPARATE REACT WEB APP, not a Flutter screen. Keyboard, hover, focus and pointer states apply; do not import mobile assumptions. Built across Phases 10a, 10b and 10c — one app, one auth, one audit log.

SECURITY IS MANDATORY AND SPECIFIED, not left to judgment. This app renders user-authored text and approves money. A malicious provider can plant a payload in a listing description and report their own listing to guarantee an admin views it.
- React or another framework with default-on JSX escaping. Never server-render raw HTML string concatenation.
- NO `dangerouslySetInnerHTML` anywhere, enforced by an ESLint rule that FAILS THE BUILD.
- CSP: `default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`. No `unsafe-inline`, no CDN origins.
- User-authored fields render as TEXT NODES ONLY — never as HTML, never as an `href` without scheme validation.

- Every admin action is audit-logged with admin ID, timestamp, action, target and REASON. Reason is mandatory at the API level, not just the UI.
- Reversal and resolution are explicit endpoints. Never a database edit.
- CSV exports carry IDs, statuses, dates, amounts and counts ONLY — never phone numbers, names, emails or bank details. An unrestricted directory export would let every phone number on the platform leave in one click.
- VIEW-AS-USER EXCLUDES MESSAGE CONTENT. An admin reaches a thread only via a specific report or dispute that names it, scoped and separately logged.
- Suspension feeds `findVisibleProviders` — one shared query, not a per-surface filter.
- Ban and hard-delete are NOT panel actions. They stay manual database operations, deliberately.
- Kill switches: 🔧 **email is THREE separate switches (OTP / notification / marketing)**, backed by three SES configuration sets. A single one would kill OTP and lock every user out of authentication. *This line used to say SMS; there is no SMS anywhere in this system — OTP goes to email, and SES is the only transactional sender.*
- Alerts de-duplicate per threshold crossing — once on cross, again only after clear and re-cross. An alert firing every fifteen minutes gets muted within a day.
- TOTP MFA and session controls ARE in scope as of Round 12 — Phase 2 builds them, every admin account must enrol before taking any action, and this panel enforces re-authentication before an identity document is viewed. Any older text telling you to skip them is obsolete.
- DO NOT BUILD, deliberately out of scope: IP allowlisting, second-admin sign-off, bulk queue actions, keyboard triage, a proactive risk-signal dashboard, broadcast messaging, or general booking-state override beyond dispute and `payment_unresolved` resolution.
