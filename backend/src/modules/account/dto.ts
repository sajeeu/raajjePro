import type { UserWithProfile } from '../auth/repository.js';

/**
 * The Profile screen's one read (plan §Phase 6, `GET /v1/users/me/profile-summary`).
 *
 * §Phase 6 names the endpoint and describes it as "one call for the Profile
 * screen"; it names no fields. So this shape is exactly what
 * `Profile.dc.html` renders and nothing else, and every field a reader might
 * expect to find here is absent for a stated reason:
 *
 * - **No phone number.** backend/CLAUDE.md excludes phone numbers
 *   structurally in the mapping layer rather than per handler, and the Profile
 *   screen displays none. An own-read is permitted to carry one — `userDto`
 *   does — but a field nothing renders is a field with nothing protecting it.
 * - **No avatar.** `User` has no avatar column and none was added: §Phase 6
 *   does not mention a photo, and media upload via presigned URL with
 *   content-type validation and EXIF stripping is §Phase 8's. The screen
 *   renders initials and its change-photo control is inert
 *   (`docs/decisions/18-phase-6-customer-profile.md`, decision 2).
 * - **No island or location.** The prototype's hero reads
 *   `Malé, Maldives · Member since Jan 2026`. There is no customer island
 *   field anywhere in this schema and `Island` itself is §Phase 7's seed, so
 *   the location half of that line cannot be answered honestly and the screen
 *   renders the member-since half alone.
 * - **No saved or booking counts.** §Phase 14's Done-when ("Profile's count
 *   updates") and §Phase 17's tabs are what put numbers on this screen. This
 *   is the call they extend — additively, per the /v1 contract — and neither
 *   `Favorite` nor `Booking` exists yet, so a count today could only be a
 *   zero that means "not built".
 *
 * `isProvider` is here because §Phase 6's role switcher routes on it: a first
 * switch goes to §Phase 6a's onboarding and every later one to §Phase 10's
 * dashboard, and this is the field that tells them apart. It is reliable
 * because a provider-profile *read* no longer creates the row
 * (`docs/decisions/17-phase-5-provider-profiles.md`, decision 11).
 */
export interface ProfileSummaryDto {
  id: string;
  fullName: string;
  /** `createdAt`, named for the one thing the screen prints from it. */
  memberSince: string;
  isProvider: boolean;
}

export function profileSummaryDto(user: UserWithProfile): ProfileSummaryDto {
  return {
    id: user.id,
    fullName: user.fullName,
    memberSince: user.createdAt.toISOString(),
    isProvider: user.providerProfile !== null,
  };
}
