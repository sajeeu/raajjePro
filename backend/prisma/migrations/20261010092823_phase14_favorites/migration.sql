-- CreateTable
CREATE TABLE "favorite_listing" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "saved_at" TIMESTAMPTZ(6) NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "favorite_listing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "favorite_provider" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "saved_at" TIMESTAMPTZ(6) NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "favorite_provider_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "favorite_listing_user_id_deleted_at_saved_at_idx" ON "favorite_listing"("user_id", "deleted_at", "saved_at");

-- CreateIndex
CREATE UNIQUE INDEX "favorite_listing_user_id_listing_id_key" ON "favorite_listing"("user_id", "listing_id");

-- CreateIndex
CREATE INDEX "favorite_provider_user_id_deleted_at_saved_at_idx" ON "favorite_provider"("user_id", "deleted_at", "saved_at");

-- CreateIndex
CREATE UNIQUE INDEX "favorite_provider_user_id_provider_profile_id_key" ON "favorite_provider"("user_id", "provider_profile_id");

-- AddForeignKey
ALTER TABLE "favorite_listing" ADD CONSTRAINT "favorite_listing_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "favorite_listing" ADD CONSTRAINT "favorite_listing_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "favorite_provider" ADD CONSTRAINT "favorite_provider_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "favorite_provider" ADD CONSTRAINT "favorite_provider_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
