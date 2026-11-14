import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/contact_verification.dart';
import 'package:toden_flutter/src/config/otp_keyboard.dart';
import 'package:toden_flutter/src/screens/contact_verification_settings.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/widgets/otp_input.dart';

// The workflow's `alphanumericCode` swaps the number keyboard for a
// capitalising text keyboard without autocorrect. Off (or absent), the field
// asks for exactly what it did before. Mirrors the React Native SDK's
// otpKeyboard.test.ts and the web SDK's ContactCodeEntry.test.tsx.
void main() {
  group('OtpKeyboard', () {
    test('keeps the number keyboard and the platform defaults for digits', () {
      final k = OtpKeyboard.of(alphanumeric: false, length: 6);
      expect(k.type, TextInputType.number);
      expect(k.capitalization, TextCapitalization.none);
      expect(k.autocorrect, isTrue);
      expect(k.formatters, isNull);
    });

    test('asks for letters, capitalised and never corrected, when on', () {
      final k = OtpKeyboard.of(alphanumeric: true, length: 6);
      expect(k.type, TextInputType.text);
      expect(k.capitalization, TextCapitalization.characters);
      expect(k.autocorrect, isFalse);
      expect(k.formatters, hasLength(1));
    });
  });

  group('OtpCodeFormatter', () {
    TextEditingValue edit(String before, String after) => OtpCodeFormatter(6)
        .formatEditUpdate(TextEditingValue(text: before), TextEditingValue(text: after));

    test('upper-cases and keeps letters and digits', () {
      expect(edit('K7', 'K7m').text, 'K7M');
      expect(edit('K7M', 'K7M-').text, 'K7M');
    });

    test('reads a pasted sentence rather than mashing it together', () {
      expect(edit('', 'Your code is K7MP2Q. It expires soon.').text, 'K7MP2Q');
    });

    test('cuts at the code length', () {
      expect(edit('K7MP2Q', 'K7MP2QX').text, 'K7MP2Q');
    });
  });

  group('the workflow flag', () {
    test('is off unless the workflow says true', () {
      expect(EmailVerificationConfig.fromJson({'enabled': true}).alphanumericCode, isFalse);
      expect(EmailVerificationConfig.fromJson({'alphanumericCode': true}).alphanumericCode, isTrue);
      expect(PhoneVerificationConfig.fromJson({'alphanumericCode': true}).alphanumericCode, isTrue);
      expect(PhoneVerificationConfig.fromJson({'alphanumericCode': 'yes'}).alphanumericCode, isFalse);
    });

    test('reaches the step settings for its own channel only', () {
      const config = VerificationConfig(
        apiKey: 'k',
        emailVerification: EmailVerificationConfig(enabled: true, alphanumericCode: true),
        phoneVerification: PhoneVerificationConfig(enabled: true),
      );
      expect(ContactChannelSettings.resolve(config, 'email').alphanumeric, isTrue);
      expect(ContactChannelSettings.resolve(config, 'phone').alphanumeric, isFalse);
    });
  });

  group('OtpInput', () {
    Future<TextField> field(WidgetTester tester, {required bool alphanumeric}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpInput(
            length: 6,
            style: OtpInputStyle.segmented,
            alphanumeric: alphanumeric,
            onCompleted: (_) {},
          ),
        ),
      ));
      return tester.widget<TextField>(find.byType(TextField));
    }

    testWidgets('uses the number keyboard when letters are off', (tester) async {
      final f = await field(tester, alphanumeric: false);
      expect(f.keyboardType, TextInputType.number);
      expect(f.autocorrect, isTrue);
      expect(f.inputFormatters, isNull);
    });

    testWidgets('uses the capitalising text keyboard when letters are on', (tester) async {
      final f = await field(tester, alphanumeric: true);
      expect(f.keyboardType, TextInputType.text);
      expect(f.textCapitalization, TextCapitalization.characters);
      expect(f.autocorrect, isFalse);
    });

    testWidgets('upper-cases what is typed', (tester) async {
      String? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpInput(
            length: 6,
            style: OtpInputStyle.segmented,
            alphanumeric: true,
            onCompleted: (c) => got = c,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'k7mp2q');
      expect(got, 'K7MP2Q');
    });
  });
}
