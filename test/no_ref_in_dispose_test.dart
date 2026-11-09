import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `dispose` runs AFTER a widget's element is unmounted, and Riverpod's `ref`
// throws there ("Cannot use ref after the widget was disposed"). A throw in
// dispose is not just a log line: Flutter unmounts children before parents,
// so the step's parent KeyedSubtree (holding the step's reused GlobalKey)
// never finishes unmounting, and the next visit to the step reuses a
// half-torn-down element. Its build fails, and a release build draws that
// failure as a plain grey box. That shipped on the address entrance step
// (go back from Street View, return, grey screen; 2026-10-19).
//
// Take what dispose needs while mounted (initState) and use that instead.

/// The body of every `dispose()` override in [source], braces matched.
Iterable<String> disposeBodies(String source) sync* {
  final start = RegExp(r'void\s+dispose\s*\(\s*\)\s*\{');
  for (final match in start.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '{') depth++;
      if (c == '}') depth--;
      i++;
    }
    yield source.substring(match.end, i - 1);
  }
}

void main() {
  test('finds the body of a dispose override', () {
    const sample = 'class A { void dispose() { if (x) { y(); } ref.read(p); super.dispose(); } void z() {} }';
    final bodies = disposeBodies(sample).toList();
    expect(bodies, hasLength(1));
    expect(bodies.single, contains('ref.read(p)'));
    expect(bodies.single, isNot(contains('void z')));
  });

  test('no dispose() in the SDK uses ref', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in files) {
      for (final body in disposeBodies(file.readAsStringSync())) {
        // Comments may name `ref` (to say why it is not used); code may not.
        final code = body.replaceAll(RegExp(r'//[^\n]*'), '');
        if (RegExp(r'\bref\s*\.').hasMatch(code)) offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty, reason: 'ref used inside dispose(): ${offenders.join(', ')}');
  });
}
