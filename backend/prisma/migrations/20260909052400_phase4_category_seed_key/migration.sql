-- The bootstrap's own key, so that renaming a seeded category does not make
-- the next `db:seed` re-create it under its old name. Nullable: an
-- admin-created category has none and the seed never touches it.
--
-- No backfill here. `seedCategories` adopts an existing row whose name matches
-- a seed key and whose own key is still null, stamping it on the way past —
-- which keeps the twelve names out of a migration file, where they would be a
-- second copy of the seed table to drift from.

-- AlterTable
ALTER TABLE "category" ADD COLUMN     "seed_key" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "category_seed_key_key" ON "category"("seed_key");
