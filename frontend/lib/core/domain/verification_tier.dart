/// `verificationTier` (plan §1e) — what the badge renders and what other
/// systems gate on. Three tiers plus `none`; **never a boolean.**
/// `verificationStatus` (unverified / pending / verified) is a different
/// axis — the review state of a pending submission — and is not this.
enum VerificationTier {
  none,
  bronze,
  silver,
  gold;

  /// Parses the API's lower-case string; anything unknown is `none`, which
  /// renders no badge rather than a wrong one.
  static VerificationTier parse(String? value) => switch (value) {
    'bronze' => bronze,
    'silver' => silver,
    'gold' => gold,
    _ => none,
  };

  /// `gold` outranks `silver` outranks `bronze` outranks `none`.
  bool meets(VerificationTier minimum) => index >= minimum.index;
}
