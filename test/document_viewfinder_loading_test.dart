import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/widgets/document_viewfinder.dart';
import 'package:toden_flutter/src/widgets/ui_spinner.dart';

// ─── Camera starting ──────────────────────────────────────────────────────────
//
// Until the camera's first frame, the viewfinder shows a dark frame with a
// spinner. UiSpinner fills the box it is given, so a bare one under the
// full-screen Center drew as wide as the phone and flashed on every opening of
// the document scan. It is the small spinner the React Native SDK shows.

void main() {
  testWidgets('the camera-starting spinner is small, not screen-wide',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocumentViewfinder(
            controller: null,
            isLoading: true,
            error: null,
            isBack: false,
            isProcessing: false,
            guideAspect: 1 / 2.07,
            hintLabel: 'NIN (Slip)',
            country: 'NG',
            onCapture: null,
          ),
        ),
      ),
    );

    final spinners = find.byType(UiSpinner);
    expect(spinners, findsWidgets);
    for (final element in spinners.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, lessThanOrEqualTo(kViewfinderSpinnerSize));
      expect(size.height, lessThanOrEqualTo(kViewfinderSpinnerSize));
    }
  });
}
