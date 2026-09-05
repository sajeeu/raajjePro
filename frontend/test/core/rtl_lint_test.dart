import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plan §Phase 1: the app is built RTL-ready without shipping Dhivehi —
/// directional insets and alignment *exclusively*. The analyzer has no rule
/// for this, so this test is the rule. It scans every Dart file under lib/
/// for the absolute-direction APIs and fails on any hit.
///
/// A hit that is genuinely correct (a pixel-mirrored icon painter, say)
/// may be excused by ending the line with `// rtl-ok: <reason>`.
void main() {
  const forbidden = <String, String>{
    r'EdgeInsets\.only\(': 'use EdgeInsetsDirectional.only(start:/end:)',
    r'EdgeInsets\.fromLTRB\(': 'use EdgeInsetsDirectional.fromSTEB',
    r'\bAlignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b':
        'use AlignmentDirectional',
    r'\bTextAlign\.(left|right)\b': 'use TextAlign.start / TextAlign.end',
    r'\bPositioned\.(?!fill)\w*\([^)]*\b(left|right):':
        'use PositionedDirectional(start:/end:)',
    r'\bPositioned\([^)]*\b(left|right):': 'use PositionedDirectional',
    r'\bBorderRadius\.only\(': 'use BorderRadiusDirectional.only',
    r'\bBorderRadius\.horizontal\(': 'use BorderRadiusDirectional.horizontal',
    r'\bBorder\(\s*(left|right):': 'use BorderDirectional(start:/end:)',
    r'\bAlignment\(': 'use AlignmentDirectional',
    r'\bRelativeRect\.fromLTRB\(': 'use RelativeRect.fromDirectional',
    r'\bTextDirection\.ltr\b':
        'a hardcoded direction; only the gallery may force one (rtl-ok)',
  };

  test('lib/ uses directional insets, alignment and positioning only', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from frontend/');

    final violations = <String>[];
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('// rtl-ok:')) continue;
        for (final entry in forbidden.entries) {
          if (RegExp(entry.key).hasMatch(line)) {
            violations.add(
              '${file.path}:${i + 1}: ${line.trim()}\n    → ${entry.value}',
            );
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Absolute-direction layout in lib/ (plan §Phase 1, RTL-ready):\n'
          '${violations.join('\n')}',
    );
  });
}
