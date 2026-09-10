import type { BookingMode, Category, VerificationTier } from '../../generated/prisma/client.js';

/**
 * What a category looks like on the wire.
 *
 * Every field here is public configuration — there is nothing sensitive on a
 * category — but the mapper is still the single structural gate (module
 * checklist), so a column added later is absent from responses until someone
 * adds it here on purpose. `isActive`, `createdAt` and `updatedAt` are
 * deliberately not in the public shape: the public list is active-only by
 * definition, so the flag would carry no information.
 */
export interface CategoryDto {
  id: string;
  name: string;
  description: string;
  iconIdentifier: string;
  colorToken: string;
  sortOrder: number;
  bookingMode: BookingMode;
  emergencyCapable: boolean;
  minimumLeadTimeMinutes: number;
  emergencyAcceptWindowMinutes: number | null;
  emergencyMinimumTier: VerificationTier | null;
  emergencyEtaPresetsMinutes: number[];
  quoteExpiryMinutes: number | null;
  quoteApprovalMinutes: number | null;
  callbackEligible: boolean;
  occasionPresets: string[];
  /**
   * §Phase 9's step-1 chips (§Phase 8). Suggestions only — a listing's own
   * `tags` are free text underneath them, and nothing validates a tag
   * against this list.
   */
  suggestedTags: string[];
}

/** The admin shape: the public one plus the soft-delete flag, so a deactivated row is reachable again. */
export interface AdminCategoryDto extends CategoryDto {
  isActive: boolean;
}

export function toCategoryDto(row: Category): CategoryDto {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    iconIdentifier: row.iconIdentifier,
    colorToken: row.colorToken,
    sortOrder: row.sortOrder,
    bookingMode: row.bookingMode,
    emergencyCapable: row.emergencyCapable,
    minimumLeadTimeMinutes: row.minimumLeadTimeMinutes,
    emergencyAcceptWindowMinutes: row.emergencyAcceptWindowMinutes,
    emergencyMinimumTier: row.emergencyMinimumTier,
    emergencyEtaPresetsMinutes: row.emergencyEtaPresetsMinutes,
    quoteExpiryMinutes: row.quoteExpiryMinutes,
    quoteApprovalMinutes: row.quoteApprovalMinutes,
    callbackEligible: row.callbackEligible,
    occasionPresets: row.occasionPresets,
    suggestedTags: row.suggestedTags,
  };
}

export function toAdminCategoryDto(row: Category): AdminCategoryDto {
  return { ...toCategoryDto(row), isActive: row.isActive };
}
