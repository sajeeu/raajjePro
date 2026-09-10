import type { BookingMode, VerificationTier } from '../../generated/prisma/client.js';

/**
 * The twelve seeded categories (plan §1d, §Phase 4).
 *
 * This table is the only place these numbers are written down. Nothing
 * downstream may hardcode one: §1c's emergency gate reads
 * `emergencyMinimumTier`, invariant 13's quote clock reads the two quote
 * windows, Round 28's guarantee reads `callbackEligible`, and all of them
 * stay admin-editable from Phase 10b — so a constant copied into a service
 * would go stale the first time an admin changes one.
 *
 * Two exceptions, as of 2026-09-10: `emergencyCapable` and
 * `emergencyMinimumTier` are **code-defined** (§Phase 10b) and the admin
 * endpoints refuse them. They are still columns, still seeded and still read
 * rather than hardcoded by consumers — what they are not is editable from the
 * panel, because admitting a category to emergency dispatch is a safety
 * decision rather than a scheduling one.
 *
 * The catalogue itself is not closed. This is seed data, not an enum: the
 * Done-when requires a thirteenth category added through the API to appear
 * in Explore with no rebuild, so no validator anywhere may check a name
 * against this list.
 *
 * `sortOrder` is the plan's own listing order, which is also the order the
 * Explore grid prototype draws (`mockups/design-composer/Discovery.dc.html`).
 */
export interface CategorySeed {
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
}

/** The arrival options an emergency offer picks from (Round 22). None is preselected in the UI. */
const ETA_TRADES = [15, 30, 45, 60];
const ETA_MOVING = [60, 90, 120, 180];

/**
 * Round 22: 30 minutes for all four capable categories, Moving included. The
 * 120 Moving briefly carried described how long a mover takes to *arrive*;
 * this field governs how long they may take to *answer*.
 */
const EMERGENCY_ANSWER_WINDOW = 30;

export const CATEGORY_SEED: readonly CategorySeed[] = [
  {
    name: 'Cleaning',
    description:
      'Home and office cleaning — regular visits, deep cleans, and move-in or move-out cleaning.',
    iconIdentifier: 'sparkle',
    colorToken: 'indigo',
    sortOrder: 1,
    bookingMode: 'slot',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 180,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    // Slot categories do not quote (§1c).
    quoteExpiryMinutes: null,
    quoteApprovalMinutes: null,
    // Round 28: a clean either happened or did not — there is nothing to un-fix.
    callbackEligible: false,
    occasionPresets: [],
  },
  {
    name: 'Plumbing',
    description: 'Leaks, blockages, taps, pipework, water heaters and bathroom fittings.',
    iconIdentifier: 'droplet',
    colorToken: 'emerald',
    sortOrder: 2,
    bookingMode: 'request',
    emergencyCapable: true,
    minimumLeadTimeMinutes: 60,
    emergencyAcceptWindowMinutes: EMERGENCY_ANSWER_WINDOW,
    // Gold, not silver: a 2am plumbing failure is life-safety work in a
    // stranger's home, and Gold is the only tier carrying a trade certificate.
    emergencyMinimumTier: 'gold',
    emergencyEtaPresetsMinutes: ETA_TRADES,
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'Electrical',
    description: 'Wiring, sockets, switches, lighting, distribution boards and fault finding.',
    iconIdentifier: 'bolt',
    colorToken: 'amber',
    sortOrder: 3,
    bookingMode: 'request',
    emergencyCapable: true,
    minimumLeadTimeMinutes: 60,
    emergencyAcceptWindowMinutes: EMERGENCY_ANSWER_WINDOW,
    emergencyMinimumTier: 'gold',
    emergencyEtaPresetsMinutes: ETA_TRADES,
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'AC Repair',
    description: 'Air-conditioning servicing, gas refills, installation and breakdown repair.',
    iconIdentifier: 'wind',
    colorToken: 'blue',
    sortOrder: 4,
    bookingMode: 'request',
    emergencyCapable: true,
    minimumLeadTimeMinutes: 60,
    emergencyAcceptWindowMinutes: EMERGENCY_ANSWER_WINDOW,
    emergencyMinimumTier: 'silver',
    emergencyEtaPresetsMinutes: ETA_TRADES,
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'Beauty',
    description: 'Hair, nails, threading, facials, make-up and salon treatments.',
    iconIdentifier: 'heart',
    colorToken: 'pink',
    sortOrder: 5,
    bookingMode: 'slot',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 120,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    quoteExpiryMinutes: null,
    quoteApprovalMinutes: null,
    callbackEligible: false,
    occasionPresets: [],
  },
  {
    name: 'Photography',
    description: 'Weddings, events, portraits, products and drone work, including editing.',
    iconIdentifier: 'camera',
    colorToken: 'orange',
    sortOrder: 6,
    bookingMode: 'request',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 1440,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    // The long window: planning genuinely happens here.
    quoteExpiryMinutes: 1440,
    quoteApprovalMinutes: 4320,
    callbackEligible: false,
    occasionPresets: [
      'Wedding',
      'Birthday',
      'Engagement',
      'Corporate',
      'Graduation',
      'Family',
      'Other',
    ],
  },
  {
    name: 'Pest Control',
    description: 'Cockroach, bedbug, termite, ant and rodent treatment, and follow-up visits.',
    iconIdentifier: 'bug',
    colorToken: 'green',
    sortOrder: 7,
    bookingMode: 'request',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 180,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    // An infestation is closer to a blocked drain than to a wedding (Round 25).
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'Appliance Repair',
    description:
      'Washing machines, refrigerators, ovens and TVs, plus computers and phones. Air-conditioning is AC Repair.',
    iconIdentifier: 'appliance',
    colorToken: 'sky',
    sortOrder: 8,
    bookingMode: 'request',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 120,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'Moving',
    description: 'House and office moves, single-item transport, packing and loading.',
    iconIdentifier: 'box',
    colorToken: 'burntOrange',
    sortOrder: 9,
    bookingMode: 'request',
    emergencyCapable: true,
    minimumLeadTimeMinutes: 1440,
    emergencyAcceptWindowMinutes: EMERGENCY_ANSWER_WINDOW,
    emergencyMinimumTier: 'silver',
    emergencyEtaPresetsMinutes: ETA_MOVING,
    quoteExpiryMinutes: 1440,
    quoteApprovalMinutes: 4320,
    // A move happened or it did not; a free repeat move has no referent.
    callbackEligible: false,
    occasionPresets: [],
  },
  {
    name: 'Fitness',
    description: 'Personal training, group sessions, yoga and swimming instruction.',
    iconIdentifier: 'dumbbell',
    colorToken: 'violet',
    sortOrder: 10,
    bookingMode: 'slot',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 120,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    quoteExpiryMinutes: null,
    quoteApprovalMinutes: null,
    callbackEligible: false,
    occasionPresets: [],
  },
  {
    name: 'Home Repairs',
    description:
      'Small household jobs — partial painting, tile replacement, mounting and hanging, sealing and grouting, minor carpentry.',
    iconIdentifier: 'hammer',
    colorToken: 'yellow',
    sortOrder: 11,
    bookingMode: 'request',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 180,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    // Round 51: the short window. A same-day household trade; nobody waits a
    // day for a quote on a cracked tile.
    quoteExpiryMinutes: 120,
    quoteApprovalMinutes: 240,
    callbackEligible: true,
    occasionPresets: [],
  },
  {
    name: 'Boat Charter',
    description: 'Picnic island trips, fishing, sandbank excursions and island hopping.',
    iconIdentifier: 'boat',
    colorToken: 'cyan',
    sortOrder: 12,
    bookingMode: 'request',
    emergencyCapable: false,
    minimumLeadTimeMinutes: 1440,
    emergencyAcceptWindowMinutes: null,
    emergencyMinimumTier: null,
    emergencyEtaPresetsMinutes: [],
    quoteExpiryMinutes: 1440,
    quoteApprovalMinutes: 4320,
    callbackEligible: false,
    occasionPresets: [
      'Fishing trip',
      'Sandbank trip',
      'Picnic island trip',
      'Sunset cruise',
      'Snorkeling trip',
      'Island hopping',
      'Other',
    ],
  },
];
