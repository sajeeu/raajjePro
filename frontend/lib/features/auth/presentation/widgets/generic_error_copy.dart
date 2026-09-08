/// The fixed fallback copy for any server error a screen has no specific
/// message for — never the server's own `message` field, which is meant for
/// logs and support tooling, never display (routing is on `code` alone).
/// Sign In, Register and Verify Email already rendered this text as a
/// literal; this is the one place it is written down, so the three change
/// forms' fallbacks (final review #8) round out to the same copy rather than
/// leaking whatever string the API happened to send.
const genericErrorCopy = 'Something went wrong. Please try again.';
