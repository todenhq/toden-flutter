import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_scan_timeline.dart';
import 'package:toden_flutter/src/config/document_specimen.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
import 'package:toden_flutter/src/widgets/document_scan_preview.dart';

// ─── The document intro's picture ─────────────────────────────────────────────
//
// The chosen document in the camera's frame marks: read, a tick, and for two
// sides a turn to the back. The numbers are the web SDK's DocumentScanPreview's.

const _card = DocumentSpecimenSubject(
  idType: 'ghana-card',
  title: 'Ghana Card',
  country: 'Ghana',
  side: SpecimenSide.front,
);

Widget _host(double width, {bool still = false, bool twoSided = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Center(
          child: SizedBox(
            width: width,
            child: DocumentScanPreview(
              subject: _card,
              aspect: 1.586,
              twoSided: twoSided,
              accent: const Color(0xFF5645F5),
            ),
          ),
        ),
      ),
    );

void main() {
  group('the timeline', () {
    test('comes in once, then a band of light reads it, then the tick', () {
      expect(documentScanFrameAt(0, twoSided: false).opacity, 0);
      expect(documentScanFrameAt(kScanComingIn, twoSided: false).opacity, 1);
      final reading = documentScanFrameAt(kScanComingIn + kScanSeconds / 2,
          twoSided: false);
      expect(reading.band, closeTo(0.5, 1e-9));
      expect(reading.bandOpacity, 1);
      expect(reading.passed, isFalse);
      final ticked = documentScanFrameAt(kScanComingIn + kScanSeconds + 0.1,
          twoSided: false);
      expect(ticked.passed, isTrue);
      expect(ticked.bandOpacity, 0);
      final after = documentScanFrameAt(
          kScanComingIn + kScanSeconds + kScanPass + 0.05,
          twoSided: false);
      expect(after.passed, isFalse);
    });

    test('a one-sided document never turns, and is read again after a rest',
        () {
      for (var t = 0.0; t < 20; t += 0.05) {
        final f = documentScanFrameAt(t, twoSided: false);
        expect(f.turn, 0);
        expect(f.lift, 0);
      }
      const lap = kScanSeconds + kScanPass + kScanRest * 3;
      final again = documentScanFrameAt(kScanComingIn + lap + kScanSeconds / 2,
          twoSided: false);
      expect(again.bandOpacity, 1);
    });

    test('a two-sided document turns over, is read on the back, and turns back',
        () {
      const turnStarts = kScanComingIn + kScanSeconds + kScanPass + kScanRest;
      expect(documentScanFrameAt(turnStarts, twoSided: true).turn, 0);
      final edgeOn =
          documentScanFrameAt(turnStarts + kScanFlip / 2, twoSided: true);
      expect(edgeOn.turn, closeTo(0.5, 1e-9));
      expect(edgeOn.lift, closeTo(1, 1e-9));
      final back = documentScanFrameAt(
          kScanComingIn + kScanSide + kScanSeconds / 2,
          twoSided: true);
      expect(back.turn, 1);
      expect(back.bandOpacity, 1);
      final home = documentScanFrameAt(kScanComingIn + kScanSide * 2 - 0.001,
          twoSided: true);
      expect(home.turn, closeTo(2, 0.01));
    });
  });

  testWidgets(
      'takes the room it has, within its bounds, with room for the marks',
      (tester) async {
    for (final (room, doc) in [
      (300.0, 260.0),
      (250.0, 210.0),
      (600.0, 340.0)
    ]) {
      await tester.pumpWidget(_host(room, still: true));
      final box =
          tester.getSize(find.byKey(const ValueKey('document-scan-frame')));
      expect(box.width, doc + 40, reason: 'room $room');
      expect(box.height, (doc / 1.586).roundToDouble() + 44,
          reason: 'room $room');
    }
    expect(
      find.descendant(
          of: find.byType(DocumentScanPreview),
          matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
  });

  testWidgets('with less motion it is the still front', (tester) async {
    await tester.pumpWidget(_host(320, still: true));
    // It settles: nothing keeps asking for frames.
    await tester.pumpAndSettle();
  });

  testWidgets('moves when motion is allowed', (tester) async {
    await tester.pumpWidget(_host(320));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
