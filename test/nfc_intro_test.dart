import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/nfc_intro.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/screens/nfc_intro_view.dart';
import 'package:toden_flutter/src/widgets/ui_button.dart';

void main() {
  group('the chip intro wording', () {
    test('a passport: the front cover, then the back cover', () {
      final copy = nfcIntroCopy(
        passport: true,
        platform: NfcIntroPlatform.ios,
        needsCode: false,
      );
      expect(copy.title, 'Your passport has a chip');
      expect(
        [
          for (final r in copy.rows) [r.icon, r.title, r.caption, r.done]
        ],
        [
          [
            NfcIntroIcon.camera,
            'Photo page scanned',
            'Its printed code unlocks the chip.',
            true
          ],
          [
            NfcIntroIcon.passport,
            'Close your passport',
            'Lay it on a flat surface.',
            false
          ],
          [
            NfcIntroIcon.phone,
            'Place your phone on the front cover',
            'Rest the top of your iPhone on it.',
            false
          ],
          [
            NfcIntroIcon.hold,
            'Hold still for a few seconds',
            'If nothing happens, try the back cover.',
            false
          ],
        ],
      );
      expect(copy.beforeTap, 'Take off a thick phone case');
    });

    test('names where the reader is on an Android phone', () {
      final copy = nfcIntroCopy(
        passport: false,
        platform: NfcIntroPlatform.android,
        needsCode: false,
      );
      expect(copy.rows[2].title, 'Place your phone on the card');
      expect(copy.rows[2].caption,
          'Rest the middle of the back of your phone on it.');
    });

    test('leaves the photo-page scan to do when the code is still needed', () {
      final copy = nfcIntroCopy(
        passport: true,
        platform: NfcIntroPlatform.android,
        needsCode: true,
      );
      expect(copy.rows, hasLength(4));
      expect(copy.rows.first.title, 'Scan the photo page');
      expect(copy.rows.first.done, isFalse);
    });

    test('knows a passport by its key', () {
      expect(isPassportId('passport'), isTrue);
      expect(isPassportId('voters-card'), isFalse);
      expect(isPassportId(null), isFalse);
    });
  });

  testWidgets('shows the steps and waits for Continue', (tester) async {
    var continued = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: NfcIntroView(
            passport: true,
            needsCode: false,
            platform: NfcIntroPlatform.android,
            onContinue: () => continued = true,
          ),
        ),
      ),
    ));
    expect(
      find.text('Rest the middle of the back of your phone on it.'),
      findsOneWidget,
    );
    expect(continued, isFalse);
    // The illustration loops, so pump fixed frames rather than settling.
    final button = find.widgetWithText(UiButton, 'Continue');
    await tester.ensureVisible(button);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 300));
    expect(continued, isTrue);
  });
}
