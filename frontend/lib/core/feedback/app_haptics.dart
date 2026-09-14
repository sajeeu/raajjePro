import 'dart:async';

import 'package:flutter/services.dart';

/// The haptic vocabulary, so a call site says **what happened** rather than
/// which vibration to play.
///
/// 🔧 **Owner's decision, 2026-09-14.** The plan specifies no haptics
/// anywhere and this was added on an explicit instruction, not inferred —
/// §Phase 1's accessibility baseline covers touch targets, contrast,
/// semantics, text scale and reduced motion, and says nothing about touch
/// feedback. §Phase 1's record carries the reasoning.
///
/// ## Three events, and why only three
///
/// Haptics on every tap is noise, and noise is worse than silence: a device
/// that buzzes constantly teaches its owner to ignore it, which costs you the
/// one channel that still works when someone is not looking at the screen.
/// So the vocabulary is deliberately small and each entry has to earn its
/// place by marking something the eye might miss.
///
///  - [selection] — a choice changed. The lightest tick there is, matching
///    what the platform plays for a picker.
///  - [commit] — something happened that the provider or customer cannot
///    quietly undo: a listing published, a booking accepted, a payment
///    attested.
///  - [refused] — the app said no. Distinct from [commit] so a failed submit
///    never feels like a successful one, which is the only pairing here where
///    confusing the two has a real cost.
///
/// ## What this does not do
///
/// It does not check a setting of ours. Both platforms already gate haptics
/// on a system preference — Android's touch-feedback toggle, iOS's System
/// Haptics — and `HapticFeedback` respects them, so a second switch in this
/// app would be a second source of truth for something the OS already owns.
///
/// It is also **not** tied to reduced motion. That setting is about movement
/// on screen; someone who turns animation off has not asked their phone to
/// stop vibrating, and conflating the two would take feedback away from the
/// people most likely to be relying on it.
/// Every entry returns `void` rather than the `Future` the platform call
/// hands back. Nothing should ever wait on a vibration before updating what
/// is on screen — and a call site that could `await` one eventually will, on
/// the slowest device, where the delay is most visible.
abstract final class AppHaptics {
  /// A choice changed — a toggle, a chip, a row in a picker, a tab.
  static void selection() => unawaited(HapticFeedback.selectionClick());

  /// Something consequential landed and is not quietly undoable.
  static void commit() => unawaited(HapticFeedback.mediumImpact());

  /// The app refused: validation failed, or a rule said no.
  static void refused() => unawaited(HapticFeedback.heavyImpact());
}
