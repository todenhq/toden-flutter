import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/widgets/document_cropper.dart';

// ─── The photo cropper takes the workflow's colours ──────────────────────────
//
// It used to paint a fixed navy bar, white text and the static Myaza purple
// whatever the workflow's appearance said (2026-09-15). The route is pushed
// outside the flow's own Theme, so document_capture_screen hands it the flow
// theme; this pins that the screen reads it. The screen now looks like the scan
// screen it opens from: a black stage and the dark glass controls in both
// themes, with the workflow's brand on the primary button.

// A 1×1 PNG, so the cropper has an image to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  for (final (name, base) in [
    ('light', UiColorScheme.light),
    ('dark', UiColorScheme.dark),
  ]) {
    testWidgets('takes the workflow colours ($name)', (tester) async {
      final scheme = base.copyWith(
        primary: const Color(0xFFD9480F),
        onPrimary: const Color(0xFFFFF4E6),
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [scheme]),
        home: DocumentCropperScreen(imageBytes: _png),
      ));

      // No app bar: the title sits on the stage, in white.
      expect(find.byType(AppBar), findsNothing);
      final title = tester.widget<Text>(find.text('Fit your ID in the frame'));
      expect(title.style?.color, const Color(0xFFFFFFFF));

      // The primary button is the flow's brand, its label on-primary.
      final label = tester.widget<Text>(find.text('Use photo'));
      expect(label.style?.color, scheme.onPrimary);
      final fill = tester.widget<Container>(find
          .ancestor(of: find.text('Use photo'), matching: find.byType(Container))
          .first);
      expect((fill.decoration as ShapeDecoration).color, scheme.primary);
      expect(tester.getSize(find.byWidget(fill)).height, 52);

      // The photo stage is black in both themes.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFF000000),
      );
    });
  }
}
