import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/business_application.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/screens/business_document_upload_card.dart';

// The uploaded row holds a thumbnail and two 48pt actions, which leaves little
// for the status line on a phone 360 wide. It has to wrap: a Row there overflows
// and draws the file size under the actions.

Widget host(double width, Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.dark]),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

BusinessDocumentUploadCard card() => BusinessDocumentUploadCard(
      title: 'Legal presence',
      uploaded: const BusinessDocumentUpload(
        type: 'incorporation_certificate',
        mediaId: 'med_1',
        fileName: 'Transika Certificate of Incorporation.pdf',
        size: 324 * 1024,
      ),
      uploading: false,
      error: null,
      previewBytes: null,
      isPdf: true,
      onChoose: () {},
      onRemove: () {},
    );

void main() {
  for (final width in [230.0, 294.0, 390.0]) {
    testWidgets('the status line fits a row $width wide', (tester) async {
      await tester.pumpWidget(host(width, card()));
      expect(tester.takeException(), isNull);
      expect(find.text('324 KB'), findsOneWidget);
    });
  }

  testWidgets('and at the largest text size', (tester) async {
    await tester.pumpWidget(host(
      294,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: card(),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
