import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/push/push_controller.dart';
import 'package:raajjepro/shared/feedback/notice_banner.dart';

/// The persistent reminder §Phase 3c asks for: *"You may miss booking
/// requests — enable notifications."*
///
/// Persistent, and deliberately not dismissible. It is not a nag about a
/// preference — the app offers no switch for booking notifications, because
/// they are transactional — it is a statement about a real gap the user
/// created at the OS level and only the OS can close. It disappears the
/// moment the permission is granted, and never otherwise.
///
/// It renders nothing when no push vendor is wired in
/// (docs/decisions/15-phase-3c-push.md): telling someone to enable
/// notifications that nothing is sending would be untrue.
///
/// Provider surfaces mount this at the top of their body — My Services
/// Dashboard (Phase 10) is the first. Mounting it is the screen's job; what
/// it says and when it shows is this widget's.
class PushDeniedReminder extends ConsumerWidget {
  const PushDeniedReminder({super.key, this.onOpenSettings});

  /// Opens the OS notification settings. Optional: without it the reminder
  /// still states the problem, which is the part that matters.
  final VoidCallback? onOpenSettings;

  static const message =
      'You may miss booking requests — enable notifications.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushControllerProvider);
    if (!push.shouldWarnDenied) return const SizedBox.shrink();

    final open = onOpenSettings;
    return NoticeBanner(
      message: message,
      icon: Icons.notifications_off_outlined,
      semanticLabel:
          'Notifications are turned off for RaajjePro. '
          'You may miss booking requests.',
      actionLabel: open == null ? null : 'Open settings',
      onAction: open,
    );
  }
}
