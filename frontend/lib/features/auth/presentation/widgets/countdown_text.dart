import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/clock.dart';

/// `m:ss` until [until], ticking once a second from the injected clock.
/// Calls [onDone] once when it reaches zero. Two of these on Verify Email are
/// two different timers — resend cooldown and rate-limit wait — and are never
/// rendered as one.
class CountdownText extends ConsumerStatefulWidget {
  const CountdownText({
    required this.until,
    required this.format,
    super.key,
    this.onDone,
    this.style,
  });
  final DateTime until;
  final String Function(String mmss) format;
  final VoidCallback? onDone;
  final TextStyle? style;

  static String mmss(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  ConsumerState<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends ConsumerState<CountdownText> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final remaining = widget.until.difference(ref.read(clockProvider)());
    if (remaining.inSeconds <= 0 && !_done) {
      _done = true;
      widget.onDone?.call();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.until.difference(ref.watch(clockProvider)());
    return Text(
      widget.format(CountdownText.mmss(remaining)),
      style: widget.style,
    );
  }
}
