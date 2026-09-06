# API versioning policy

**Status: in effect from Phase 2. Plan revision 5.19, §2 "API versioning".**

## 1. Rule

Everything under `/v1` evolves additive-only. The plan requires this because
installed mobile clients cannot be force-updated: whatever version of the app
is on a customer's or provider's phone today has to keep working against
whatever the backend serves tomorrow, indefinitely, until that person updates
the app on their own schedule. A change that an old client cannot parse or
that changes what an old client's request means is a change that breaks a
device already in someone's pocket.

## 2. What is breaking

- Removing or renaming a response field, an error `code`, or a route.
- Changing a field's type or its meaning (same name, different semantics).
- Tightening request validation in a way a current client's requests would
  now fail.
- Changing a default value a client relies on implicitly.
- Making a previously-optional request field required.
- Changing what an existing enum value means (as opposed to adding a new one).

Any of these ships in `/v2`, never patched into `/v1`.

## 3. What is additive

- A new optional response field.
- A new route.
- A new enum value — clients are told, in this document and in the field's
  description, to treat an enum value they don't recognise as equivalent to
  an "other" case rather than erroring.
- A new error `code` on a genuinely new failure condition.
- Loosening request validation (accepting more than before).

Any of these can land directly in `/v1`.

## 4. Deprecating a field

A field is never pulled out from under `/v1` clients. To retire one:

1. Keep serving it, with its old value, unchanged.
2. Document it here — the field, the date it was deprecated, and its
   replacement.
3. The owning route sets `Deprecation: true` and `Sunset: <date>` response
   headers.
4. Monitor whether anything still reads it via the request log (method, path,
   status, duration — no bodies, per `backend/CLAUDE.md`'s logging rule).
5. Remove it only when `/v2` ships; `/v1` keeps serving it until then.

_No field has been deprecated yet._

## 5. When a breaking change is unavoidable

`/v2` is stood up beside `/v1` — never replacing it in place. `/v1` keeps
running until Phase 21's product event stream shows no installed client
version has called the endpoint in question for 90 days. From Phase 20
onward the Flutter app carries a minimum-supported-version check; that check
is a pointer for customer messaging ("please update"), not a mechanism that
forces an upgrade or blocks the old client from calling `/v1`.

## 6. Error codes are API

Error codes are stable, machine-readable identifiers the frontend routes on,
not prose. They live in `backend/src/core/errors.ts` (the seven error classes
and their fixed statuses) and in each module's service, where a module-specific
`code` string is supplied to the class it throws (e.g. `IDEMPOTENCY_KEY_REUSED`,
`MFA_ENROLMENT_REQUIRED`). Renaming a code follows the same deprecation
process as a field: the old code keeps being returned, the new one is
documented as its replacement, and the old one is removed only in `/v2`.
