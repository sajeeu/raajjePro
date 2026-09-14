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
  late final AnimationController _controller = AnimationController(vsync: this);
  late Animation<double> _entrance;
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
      _controller.duration = AppMotion.page;
      _entrance = _controller;
      _controller.value = 1;
      return;
    }

    // 🔧 **The stagger is an `Interval`, not a delayed start.** The obvious
    // way to hold an item back is `Future.delayed(...).then(forward)`, and it
    // works — but the timer outlives a widget test that finishes inside the
    // delay, and the framework fails the test with "pending timers" rather
    // than the assertion it was making. `phase6_done_when_test.dart` caught
    // it on three tests at once.
    //
    // Folding the delay into the curve removes the timer entirely: one
    // controller running `delay + page`, flat for the first stretch. It also
    // cancels with `dispose`, which a bare `Future.delayed` does not.
    final delay = motion.staggerFor(widget.index);
    final total = delay + AppMotion.page;
    _controller.duration = total;
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.easeOut,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = AppMotion.of(context).fadeUpSlide;
    return AnimatedBuilder(
      animation: _entrance,
      // Built once and reused: the child does not depend on the animation,
      // so rebuilding it every frame of a 350 ms entrance would be the most
      // expensive way to do the cheapest thing.
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        // 🔧 **Semantics do not fade.** `RenderOpacity` drops its child from
        // the semantics tree entirely at alpha 0, so without this a screen
        // reader loses the whole page for the length of its entrance —
        // longer for a staggered item, which starts later. Content that is
        // arriving is still content, and a reader that reaches it before the
        // pixels do has lost nothing.
        //
        // Caught by `sign_in_screen_test.dart`, which finds its four
        // third-party buttons by semantics label: the text finders passed and
        // the semantics finders returned nothing, which is the signature.
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - _entrance.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A [Column] whose children enter with [FadeUp], each one step behind the
/// last.
///
/// A drop-in replacement, so adopting the entrance on a screen is one word
/// rather than a rewrite — which matters because there is no shared scaffold
/// here: all twenty screens build their own, and an entrance applied by hand
/// to each would drift by the third one.
///
/// Wrap the screen's **content** column, not its outermost one. Wrapping the
/// outermost gives every child the same index and the whole page arrives as a
/// block, which is the thing this exists to remove.
class FadeUpColumn extends StatelessWidget {
  const FadeUpColumn({
    required this.children,
    super.key,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    children: fadeUpAll(children),
  );
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
