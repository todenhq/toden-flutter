import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/prompt_timeline.dart';

void main() {
  test('reports each prompt against the start of the recording', () {
    final t = PromptTimeline()
      ..shown('turn', 2000)
      ..passed(3400)
      ..shown('smile', 5100)
      ..passed(6200);
    expect(t.report(1000), [
      {'prompt': 'turn', 'shownAt': 1000, 'passedAt': 2400},
      {'prompt': 'smile', 'shownAt': 4100, 'passedAt': 5200},
    ]);
  });

  test('keeps the first time when a prompt is shown again', () {
    final t = PromptTimeline()
      ..shown('blink', 1000)
      ..shown('blink', 4000)
      ..passed(5000);
    expect(t.report(0), [
      {'prompt': 'blink', 'shownAt': 1000, 'passedAt': 5000},
    ]);
  });

  test('leaves out the flash, the passive hold and a prompt that never passed', () {
    final t = PromptTimeline()
      ..shown('flash', 100)
      ..shown('hold', 200)
      ..passed(300);
    expect(t.report(0), isNull);
    t.shown('turn', 400);
    expect(t.report(0), isNull);
  });

  test('counts a prompt shown before the recorder went live from the first frame', () {
    final t = PromptTimeline()
      ..shown('turn', 900)
      ..passed(2000);
    expect(t.report(1000), [
      {'prompt': 'turn', 'shownAt': 0, 'passedAt': 1000},
    ]);
  });

  test('reports nothing with no recording, and nothing after a retry', () {
    final t = PromptTimeline()
      ..shown('turn', 100)
      ..passed(200);
    expect(t.report(null), isNull);
    t.reset();
    expect(t.report(0), isNull);
  });
}
