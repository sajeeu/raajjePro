-- CreateTable
CREATE TABLE "island" (
    "id" UUID NOT NULL,
    "seed_key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "atoll_name" TEXT NOT NULL,
    "atoll_abbr" TEXT NOT NULL,
    "name_ambiguous" BOOLEAN NOT NULL,
    "search_name" TEXT NOT NULL,
    "search_qualified" TEXT NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "island_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_service_area" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "island_id" UUID NOT NULL,
    "added_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "removed_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_service_area_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "island_seed_key_key" ON "island"("seed_key");

-- CreateIndex
CREATE INDEX "island_is_active_name_idx" ON "island"("is_active", "name");

-- CreateIndex
CREATE INDEX "island_search_qualified_idx" ON "island"("search_qualified");

-- CreateIndex
CREATE UNIQUE INDEX "island_atoll_abbr_name_key" ON "island"("atoll_abbr", "name");

-- CreateIndex
CREATE INDEX "provider_service_area_island_id_removed_at_idx" ON "provider_service_area"("island_id", "removed_at");

-- CreateIndex
CREATE UNIQUE INDEX "provider_service_area_provider_profile_id_island_id_key" ON "provider_service_area"("provider_profile_id", "island_id");

-- AddForeignKey
ALTER TABLE "provider_service_area" ADD CONSTRAINT "provider_service_area_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_service_area" ADD CONSTRAINT "provider_service_area_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
