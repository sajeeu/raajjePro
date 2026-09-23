-- §Phase 17.2 — the request-with-quote path.
--
-- Four nullable columns on `booking` and two indexes. Nothing existing is
-- altered: the statuses this slice reaches (`awaiting_quote`, `quote_offered`)
-- and the `quoted` amount kind were already in the enums §Phase 17.1 created,
-- and `preferred_window_*` and `occasion` were already columns waiting for a
-- writer.

-- The provider's deadline to quote — `created_at + category.quote_expiry_minutes`.
ALTER TABLE "booking" ADD COLUMN "quote_due_at" TIMESTAMPTZ(6);

-- The live quote's own clock, and the customer's deadline to approve it —
-- `quote_offered_at + category.quote_approval_minutes`. Stored rather than
-- recomputed: an admin editing the category must not move a countdown a
-- customer is already watching.
ALTER TABLE "booking" ADD COLUMN "quote_offered_at" TIMESTAMPTZ(6);
ALTER TABLE "booking" ADD COLUMN "quote_expires_at" TIMESTAMPTZ(6);

-- The provider's note on the quote. Kept apart from `job_notes`, which is the
-- customer's own description and what §1h's amendment reads as prior scope.
ALTER TABLE "booking" ADD COLUMN "quote_note" VARCHAR(2000);

-- One indexed range scan per sweep.
CREATE INDEX "booking_status_quote_due_at_idx" ON "booking"("status", "quote_due_at");
CREATE INDEX "booking_status_quote_expires_at_idx" ON "booking"("status", "quote_expires_at");
