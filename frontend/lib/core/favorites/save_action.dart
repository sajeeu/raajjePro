import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/routes.dart';

/// What every heart does when tapped — one function, so the card, the listing
/// page, the provider page and the Saved screen behave identically.
///
/// - **A guest is sent to sign in.** §1c's access table puts saving at
///   *Registered*; the server refuses a guest regardless (invariant 4), and
///   this is what spares them the refusal.
/// - **Optimistic, rolled back visibly.** The heart turns at once; if the
///   server refuses it turns back and the screen says so. The sentence is the
///   artboard's (`Discovery.dc.html`). There is no field to put it under, so
///   it is the one place a snack bar carries an error.
///
/// Returns true when the change stuck.
Future<bool> setSaved(
  BuildContext context,
  WidgetRef ref,
  FavoriteKind kind,
  String id, {
  required bool saved,
}) async {
  if (ref.read(authControllerProvider) is! AuthSignedIn) {
    await Navigator.of(context).pushNamed(AppRoutes.signIn);
    return false;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await ref
      .read(favoritesProvider.notifier)
      .set(kind, id, saved: saved);
  if (!ok) {
    AppHaptics.refused();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(saveFailedCopy(saved: saved))));
  }
  return ok;
}

/// The rollback's sentence. Unsaving says "restored" because the thing the
/// customer just watched disappear has come back.
String saveFailedCopy({required bool saved}) => saved
    ? 'Couldn’t save — check your connection.'
    : 'Couldn’t remove — restored. Check your connection.';
