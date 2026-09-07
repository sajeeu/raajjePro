/// `Too many attempts. Try again in {m:ss}.` — or, when the server didn't
/// say how long, a copy that doesn't name a duration it doesn't have.
/// Shared by Sign In and Register: the format is defined once here.
String rateLimitCopy(int? secondsRemaining) {
  if (secondsRemaining == null) return 'Try again in a moment.';
  final minutes = secondsRemaining ~/ 60;
  final seconds = secondsRemaining % 60;
  return 'Too many attempts. Try again in $minutes:${seconds.toString().padLeft(2, '0')}.';
}
