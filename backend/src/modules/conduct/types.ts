/**
 * One booking on the provider's own conduct evidence list (§1f: "with the
 * underlying bookings listed"). Each flag says which metric the booking moved;
 * none of them is a judgement, and there is no field for one.
 *
 * Returned only to the provider it is about.
 */
export interface ConductEvidenceDto {
  bookingId: string;
  reference: string;
  listingId: string;
  listingName: string;
  bookingMode: 'slot' | 'request' | 'emergency';
  completed: boolean;
  acceptedInWindow: boolean;
  providerCancelled: boolean;
  noShow: boolean;
  /** Null when the booking is not in price adherence's denominator. */
  priceAdherent: boolean | null;
  /** The explicit answer to the booking, or null when there was none in the window. */
  response: 'accepted' | 'declined' | null;
  responseSeconds: number | null;
  countedAt: string;
}
