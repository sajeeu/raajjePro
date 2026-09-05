import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// One tab. [activeIcon] defaults to [icon].
class AppNavItem {
  const AppNavItem({required this.icon, required this.label, this.activeIcon});

  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// The bottom navigation (`BottomNav.dc.html`). Five tabs; the active one
/// sits in a 52 × 30 accent-tinted pill that **slides** to the new tab over
/// `base` on `easeOut` — the "animated nav pill" motion primitive. Under
/// reduced motion the pill jumps.
///
/// Which five tabs — the customer set or the provider set — is the owning
/// screen's decision (the role switcher, Phase 6); this widget renders
/// whatever items it is given.
///
/// Two deviations from the prototype, recorded in
/// `docs/decisions/08-phase-1-design-system.md`: inactive labels use
/// `textSecondary` (5.4:1), not the measured `#8296B3` (3.0:1) — an inactive
/// tab is live, not disabled, and its 10.5 px label must clear AA; and the
/// label's text scale is clamped at 1.3×, because a five-tab bar on a phone
/// has ~70 dp per tab and at 2× "Bookings" breaks into "Bookin / gs". The
/// icon, the 48 dp target and the spoken label are unaffected.
class AnimatedBottomNav extends StatelessWidget {
  const AnimatedBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  }) : assert(items.length >= 2, 'A nav needs at least two tabs.');

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final n = items.length;

    // -1 … 1 across the row; AlignmentDirectional so it mirrors under RTL.
    final x = n == 1 ? 0.0 : -1 + 2 * currentIndex / (n - 1);

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.divider,
              width: AppSizes.dividerStroke,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.sm + 2,
              AppSpacing.sm,
              AppSpacing.sm + 2,
              AppSpacing.md,
            ),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: Stack(
                children: [
                  // The sliding pill lives behind the tabs. Each tab is
                  // 1/n of the row; the pill is centred in the active slot
                  // and sits at the top where the icon is.
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: SizedBox(
                          height: AppSizes.navPillHeight,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final slot = c.maxWidth / n;
                              return AnimatedAlign(
                                alignment: AlignmentDirectional(x, 0),
                                duration: motion.base,
                                curve: AppMotion.easeOut,
                                child: SizedBox(
                                  width: slot,
                                  child: Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.accentTint,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.pill,
                                        ),
                                      ),
                                      child: const SizedBox(
                                        width: AppSizes.navPillWidth,
                                        height: AppSizes.navPillHeight,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _Tab(
                            item: items[i],
                            active: i == currentIndex,
                            index: i,
                            count: n,
                            onTap: () => onSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  /// The most a nav label scales. See the class note on [AnimatedBottomNav].
  static const double labelMaxScale = 1.3;

  const _Tab({
    required this.item,
    required this.active,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final AppNavItem item;
  final bool active;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final motion = context.motion;
    final fg = active ? colors.accentText : colors.textSecondary;

    return Pressable(
      onTap: onTap,
      selected: active,
      semanticLabel: '${item.label}, tab ${index + 1} of $count',
      focusRadius: AppRadius.md,
      builder: (context, s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: AppSizes.navPillHeight,
            child: Center(
              child: AnimatedSwitcher(
                duration: motion.fast,
                child: Icon(
                  active ? (item.activeIcon ?? item.icon) : item.icon,
                  key: ValueKey(active),
                  size: AppSizes.navIcon,
                  color: fg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: motion.fast,
            style: type.navLabel.copyWith(color: fg),
            child: Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: _Tab.labelMaxScale),
            ),
          ),
        ],
      ),
    );
  }
}
