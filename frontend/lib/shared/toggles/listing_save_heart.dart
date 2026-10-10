import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/core/favorites/save_action.dart';
import 'package:raajjepro/shared/toggles/save_heart_toggle.dart';

/// [SaveHeartToggle] wired to §Phase 14 for one listing: it reads the app's
/// one saved state, asks the server about its listing as it appears, and
/// saves or unsaves through [setSaved] — optimistic, rolled back visibly, a
/// guest sent to sign in.
///
/// Drop it wherever a service is drawn; there is nothing for the screen
/// around it to fetch or hold.
class ListingSaveHeart extends ConsumerStatefulWidget {
  const ListingSaveHeart({
    required this.listingId,
    required this.listingName,
    super.key,
    this.style = SaveHeartStyle.overlay,
  });

  final String listingId;
  final String listingName;
  final SaveHeartStyle style;

  @override
  ConsumerState<ListingSaveHeart> createState() => _ListingSaveHeartState();
}

class _ListingSaveHeartState extends ConsumerState<ListingSaveHeart> {
  @override
  void initState() {
    super.initState();
    ref.read(favoritesProvider.notifier).ensure(listingIds: [widget.listingId]);
  }

  @override
  void didUpdateWidget(ListingSaveHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listingId != widget.listingId) {
      ref
          .read(favoritesProvider.notifier)
          .ensure(listingIds: [widget.listingId]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(
      favoritesProvider.select((s) => s.listingSaved(widget.listingId)),
    );
    return SaveHeartToggle(
      saved: saved,
      style: widget.style,
      itemName: widget.listingName,
      onChanged: (next) => unawaited(
        setSaved(
          context,
          ref,
          FavoriteKind.listing,
          widget.listingId,
          saved: next,
        ),
      ),
    );
  }
}
