import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/capture_hints.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/immersive_layout.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/widgets/document_viewfinder.dart';

// ─── The hint beside a turned guide ───────────────────────────────────────────
//
// A NIN slip on a phone held upright is framed upright, drawn a quarter turn
// clockwise, so the person turns the phone to read it. The hint pill stayed
// drawn for the upright hold and read sideways; it turns with the sample and
// sits along the guide's left edge, which is its bottom edge in that hold.

const _hint = DocumentHint.spaceAround;
// The band the screen hands down for a 440 x 956 phone with no system bars
// (the test view): the top bar + 16 above, the bottom row + 24 below.
final _band = documentGuideBand(topInset: 0, bottomInset: 0);

Widget _host(double guideAspect) => MaterialApp(
      home: Scaffold(
        body: DocumentViewfinder(
          controller: null,
          isLoading: false,
          error: null,
          isBack: false,
          isProcessing: false,
          guideAspect: guideAspect,
          guideBand: guideAspect < 1 ? _band : null,
          hint: _hint,
          hintLabel: 'NIN (Slip)',
          country: 'NG',
          onCapture: () {},
          onUpload: () {},
        ),
      ),
    );

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(440, 956);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a turned guide turns the hint and puts it beside the guide',
      (tester) async {
    await tester.pumpWidget(_host(1 / 2.07));
    expect(tester.takeException(), isNull);

    final hint = find.byKey(kDocumentHintKey);
    expect(hint, findsOneWidget);
    final box = tester.widget(hint);
    expect(box, isA<RotatedBox>());
    expect((box as RotatedBox).quarterTurns, kTurnedHintQuarterTurns);

    final guide =
        documentGuideRect(const Size(440, 956), 1 / 2.07, band: _band);
    final rect = tester.getRect(hint);
    expect(rect.right, lessThanOrEqualTo(guide.left),
        reason: 'along the guide, not over it');
    expect(rect.height, greaterThan(rect.width), reason: 'runs along it');
    expect(rect.center.dy, closeTo(guide.center.dy, 1));
    expect(
        guide.top,
        immersiveTopBarTop(0) +
            kImmersiveTopBarHeight +
            kImmersiveGuideGapBelowTopBar,
        reason: 'only the top bar above a turned guide: its hint is beside it');

    // Only the drawing turns: the words are the same for a screen reader.
    expect(find.text(documentHintText(_hint, label: 'NIN (Slip)')),
        findsOneWidget);
  });

  testWidgets('a landscape guide keeps the hint upright under the top bar',
      (tester) async {
    await tester.pumpWidget(_host(1.586));
    final hint = find.byKey(kDocumentHintKey);
    expect(hint, findsOneWidget);
    expect(find.byType(RotatedBox), findsNothing);
    final rect = tester.getRect(hint);
    expect(rect.width, greaterThan(rect.height));
    expect(rect.top, immersiveHintTop(0));
  });
}
