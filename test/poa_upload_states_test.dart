import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/screens/proof_of_address_parts.dart';
import 'package:toden_flutter/src/widgets/ui_spinner.dart';

// How the proof of address comes in: the capture tiles the workflow asks for,
// a progress row while it uploads, then the uploaded card with Replace and
// Remove. Mirrors the web SDK's PoaUploadActions and PoaUploadedCard.

Widget host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(body: SizedBox(width: 390, child: child)),
    );

void main() {
  group('capture tiles', () {
    Widget actions(PoaCapture capture, {bool uploading = false, void Function()? camera, void Function()? file}) =>
        host(PoaUploadActions(
          capture: capture,
          uploading: uploading,
          onCamera: camera ?? () {},
          onFile: file ?? () {},
        ));

    testWidgets('both by default: a photo and a file, side by side', (tester) async {
      var cameras = 0, files = 0;
      await tester.pumpWidget(actions(PoaCapture.both, camera: () => cameras++, file: () => files++));
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Use your camera'), findsOneWidget);
      expect(find.text('Upload a file'), findsOneWidget);
      expect(find.text('PDF or image'), findsOneWidget);
      await tester.tap(find.text('Take a photo'));
      await tester.tap(find.text('Upload a file'));
      expect((cameras, files), (1, 1));
    });

    testWidgets('the workflow can ask for one way only', (tester) async {
      await tester.pumpWidget(actions(PoaCapture.camera));
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Upload a file'), findsNothing);
      await tester.pumpWidget(actions(PoaCapture.file));
      expect(find.text('Take a photo'), findsNothing);
      expect(find.text('Upload a file'), findsOneWidget);
    });

    testWidgets('give way to one progress row while uploading', (tester) async {
      await tester.pumpWidget(actions(PoaCapture.both, uploading: true));
      expect(find.text('Uploading…'), findsOneWidget);
      expect(find.byType(UiSpinner), findsOneWidget);
      expect(find.text('Take a photo'), findsNothing);
    });
  });

  group('uploaded card', () {
    testWidgets('shows the file, its kind, and working Replace and Remove', (tester) async {
      var replaced = 0, removed = 0;
      await tester.pumpWidget(host(PoaUploadedCard(
        fileName: 'Screenshot 2026-07-22 at 04.02.49.png',
        typeLabel: 'Utility bill',
        previewBytes: null,
        isPdf: true,
        country: 'NG',
        onReplace: () => replaced++,
        onRemove: () => removed++,
      )));

      expect(find.text('Document uploaded'), findsOneWidget);
      expect(find.text('Screenshot 2026-07-22 at 04.02.49.png'), findsOneWidget);
      expect(find.text('Utility bill'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.tap(find.text('Remove'));
      expect((replaced, removed), (1, 1));
    });

    testWidgets('a PDF renders a document page, not a broken image', (tester) async {
      await tester.pumpWidget(host(PoaUploadedCard(
        fileName: 'statement.pdf',
        typeLabel: 'Bank statement',
        previewBytes: null,
        isPdf: true,
        onReplace: () {},
        onRemove: () {},
      )));
      expect(find.byType(PoaPage), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a restored upload with no name names its kind', (tester) async {
      await tester.pumpWidget(host(PoaUploadedCard(
        fileName: null,
        typeLabel: 'Bank statement',
        previewBytes: null,
        isPdf: false,
        onReplace: () {},
        onRemove: () {},
      )));
      expect(find.text('Bank statement'), findsNWidgets(2));
    });
  });

  group('config labels', () {
    test('otherLabel renames only the "other" kind', () {
      const cfg = ProofOfAddressConfig(
        enabled: true,
        otherLabel: 'Council tax letter',
      );
      expect(cfg.labelFor(PoaDocumentType.other), 'Council tax letter');
      expect(cfg.labelFor(PoaDocumentType.utilityBill), 'Utility bill');
    });

    test('a blank otherLabel falls back to the generic label', () {
      const cfg = ProofOfAddressConfig(enabled: true, otherLabel: '   ');
      expect(cfg.labelFor(PoaDocumentType.other), 'Other document');
    });

    test('otherLabel is parsed off a resolved workflow', () {
      final cfg = ProofOfAddressConfig.fromJson({
        'enabled': true,
        'documentTypes': ['utility_bill'],
        'maxAgeDays': 30,
        'otherLabel': 'Council tax letter',
      });
      expect(cfg.maxAgeDays, 30);
      expect(cfg.offeredTypes, [PoaDocumentType.utilityBill]);
      expect(cfg.otherLabel, 'Council tax letter');
    });
  });
}
