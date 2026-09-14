import 'package:flutter/widgets.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// `fadeUp` from `motion.css`, which 52 of the 61 artboards use and the app
/// did not implement.
///
/// ```css
/// @keyframes fadeUp { from { opacity:0; transform:translateY(14px) }
///                     to   { opacity:1; transform:none } }
/// animation: fadeUp var(--m-page) var(--e-out) both;
/// ```
///
/// Content rises 14 dp and fades in over [AppMotion.page] on
/// [AppMotion.easeOut] — the same curve and duration the page transition
/// uses, so a screen's chrome and its content share one beat instead of the
/// content simply existing the moment the slide ends. That gap is most of
/// what made the app feel rigid: the transition was implemented and the
/// entrance it was designed to hand off to was not.
///
/// Pass [index] inside a list to stagger, exactly as `My Bookings` and
/// `Discovery` do — `calc(min(index, 6) * 30ms)`, capped so a long list does
/// not make its tail wait.
///
/// **Reduced motion is not a special case here.** With the OS setting on,
/// [ResolvedMotion] hands back a zero duration, a zero rise and a zero
/// stagger, so this renders its child at rest on the first frame. It is safe
/// to wrap anything.
///
/// It animates on first build only. A [FadeUp] that rebuilds — a list that
/// repaints on scroll, a field whose value changes — does not re-run, because
/// an entrance that repeats is a flicker.
class FadeUp extends StatefulWidget {
  const FadeUp({required this.child, super.key, this.index = 0});

  final Widget child;

  /// Position in a run of siblings. 0 (the default) starts immediately.
  final int index;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.page,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = AppMotion.of(context);
    if (motion.reduced) {
      // Jump to rest rather than animating for zero time: a zero-duration
      // controller still schedules a frame, and the slide would lay out one
      // off-screen frame first — the flash `ResolvedMotion` documents.
      _controller.value = 1;
      return;
    }
    final delay = motion.staggerFor(widget.index);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = AppMotion.of(context).fadeUpSlide;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOut,
    );
    return AnimatedBuilder(
      animation: curved,
      // Built once and reused: the child does not depend on the animation,
      // so rebuilding it every frame of a 350 ms entrance would be the most
      // expensive way to do the cheapest thing.
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// [FadeUp] applied down a run of siblings, each one step behind the last.
///
/// The list equivalent of wrapping each child by hand, and the reason the
/// stagger is a helper rather than a convention: `children.indexed` is easy
/// to get subtly wrong when a list is filtered or reordered, and an entrance
/// that starts from the wrong index reads as a stutter.
List<Widget> fadeUpAll(List<Widget> children) => [
  for (final (i, child) in children.indexed) FadeUp(index: i, child: child),
];
