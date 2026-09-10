-- CreateEnum
CREATE TYPE "provider_type" AS ENUM ('individual', 'business');

-- AlterTable
ALTER TABLE "provider_profile" ADD COLUMN     "provider_type" "provider_type";
