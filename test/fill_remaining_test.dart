import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/widgets/fill_remaining.dart';

// The map and Street View run down to the Continue button on a tall phone and
// keep their usual height (the body scrolls) on a short one.

Widget _host({required double viewport, required double minimum}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        height: viewport,
        child: SingleChildScrollView(
          child: FillViewportScope(
            height: viewport,
            child: FillRemainingColumn(
              flexIndex: 0,
              minFlexHeight: minimum,
              children: const [
                SizedBox(key: Key('map')),
                SizedBox(height: 16),
                SizedBox(key: Key('summary'), height: 120),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('the map gets the rest, never less than its minimum', () {
    expect(RenderFillRemainingColumn.flexHeightFor(viewport: 800, others: 136, minimum: 300), 664);
    expect(RenderFillRemainingColumn.flexHeightFor(viewport: 400, others: 136, minimum: 300), 300);
    expect(RenderFillRemainingColumn.flexHeightFor(viewport: null, others: 136, minimum: 300), 300);
  });

  testWidgets('on a tall screen the map fills the body to the bottom', (tester) async {
    await tester.pumpWidget(_host(viewport: 800, minimum: 300));
    expect(tester.getSize(find.byKey(const Key('map'))), const Size(360, 664));
    expect(tester.getBottomLeft(find.byKey(const Key('summary'))).dy, 800);
  });

  testWidgets('on a short screen the map keeps its height and the body scrolls', (tester) async {
    await tester.pumpWidget(_host(viewport: 400, minimum: 300));
    expect(tester.getSize(find.byKey(const Key('map'))).height, 300);
    // 300 + 16 + 120 = 436, taller than the 400 viewport: it scrolls.
    expect(tester.getBottomLeft(find.byKey(const Key('summary'))).dy, 436);
  });
}
