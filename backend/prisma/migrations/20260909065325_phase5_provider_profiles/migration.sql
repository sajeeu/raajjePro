-- Phase 5 — Provider Profiles (plan §Phase 5). Additive: every column is
-- nullable or carries a default, so existing rows created by Phase 3's
-- provider-variant registration stay valid without a backfill.
--
-- What is NOT here, on purpose:
--   - no phone column: the one phone number lives on app_user (§Phase 5), and
--     a second copy would be a second thing to protect (§1c).
--   - no visibility/lifecycle column: public visibility is DERIVED from the
--     published-listing count (§1a) and computed by findVisibleProviders. The
--     v1 stored flag drifted and is never coming back.
--   - no CHECK tying maldivian_owned to the gold tier. §1g's "absent below
--     Gold" is enforced in the DTO mapper instead, so an admin demoting a tier
--     cannot be blocked by a constraint, and a re-promotion does not have to
--     re-derive an attribute the registration document already evidenced.
--
-- suspended_at is Phase 5's half of §1a's "suspension is an input to
-- visibility": the column and the filter. Phase 10b owns the admin action.

-- AlterTable
ALTER TABLE "provider_profile" ADD COLUMN     "accepting_new_customers" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "bank_account_name" TEXT,
ADD COLUMN     "bank_account_number" TEXT,
ADD COLUMN     "bank_name" TEXT,
ADD COLUMN     "bio" VARCHAR(160),
ADD COLUMN     "maldivian_owned" BOOLEAN,
ADD COLUMN     "subscription_price_laari" INTEGER,
ADD COLUMN     "suspended_at" TIMESTAMPTZ(6),
ADD COLUMN     "suspended_reason" TEXT,
ADD COLUMN     "transfer_instructions" TEXT,
ADD COLUMN     "years_of_experience" INTEGER;

-- CreateIndex
CREATE INDEX "provider_profile_suspended_at_id_idx" ON "provider_profile"("suspended_at", "id");

-- CreateIndex
CREATE INDEX "provider_profile_verification_tier_idx" ON "provider_profile"("verification_tier");
