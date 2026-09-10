-- When an account first satisfied §Phase 6a's onboarding requirements.
-- A record of an event, not a copy of the five fields the requirements read:
-- all five are legally editable, so a derived predicate answered "not
-- onboarded" for a provider who had been trading for months and cleared a
-- bank field, and §Phase 6's role switcher then routed them back into
-- onboarding, whose last step hands off to a fresh wizard draft.
--
-- No backfill. Every existing row predates the flow, and the sticky read is
-- `stamped OR meets-the-requirements-now`, so an account that already
-- qualifies keeps reading complete and is stamped on its next provider write.

-- AlterTable
ALTER TABLE "provider_profile" ADD COLUMN     "onboarding_completed_at" TIMESTAMP(3);
