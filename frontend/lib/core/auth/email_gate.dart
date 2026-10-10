import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/routes.dart';

/// §1c: booking and messaging need a verified email. Returns true when the
/// caller may go on; otherwise routes to the screen that fixes it — sign in
/// for a guest, Verify Email for an unverified account — and returns false.
///
/// It is not the check. The server refuses an unverified send on its own
/// (`requireEmailVerified`, invariant 4); this spares the customer the
/// refusal. Moved here from the provider profile by §Phase 14, whose Saved
/// providers row is its second consumer.
bool passEmailGate(BuildContext context, WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  final navigator = Navigator.of(context);
  if (auth is! AuthSignedIn) {
    navigator.pushNamed(AppRoutes.signIn);
    return false;
  }
  if (!auth.user.emailVerified) {
    navigator.pushNamed(
      AppRoutes.verifyEmail,
      arguments: <String, dynamic>{
        'email': auth.user.email,
        'purpose': 'verifyEmail',
      },
    );
    return false;
  }
  return true;
}
