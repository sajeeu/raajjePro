import 'package:flutter/material.dart';

/// Root widget. Phase 1 replaces the bare [MaterialApp] with the themed one
/// carrying the design tokens; until then this is only enough to prove the
/// app boots.
class RaajjeProApp extends StatelessWidget {
  const RaajjeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'RaajjePro',
      home: Scaffold(body: Center(child: Text('RaajjePro'))),
    );
  }
}
