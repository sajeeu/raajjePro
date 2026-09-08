import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injected time, so countdowns are tested by overriding this rather than by
/// waiting. Widgets still tick with a `Timer.periodic`; only "now" comes here.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
