import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/otp_code.dart';

// A MIRROR of the React Native SDK's __tests__/otpCode.test.ts and the web
// SDK's lib/otp-code.test.ts: the same cases with the same answers.
void main() {
  group('otpCodeFrom', () {
    test('keeps what is typed, digits only', () {
      expect(otpCodeFrom('12', '1', 6), '12');
      expect(otpCodeFrom('12a', '12', 6), '12');
    });

    test('finds the code in the sentence it was copied from', () {
      expect(otpCodeFrom('Your code is 123456. It expires soon.', '', 6), '123456');
      expect(otpCodeFrom('Order 88: your code is 123456', '', 6), '123456');
    });

    test('reads a code copied with a space or dash', () {
      expect(otpCodeFrom('123 456', '', 6), '123456');
      expect(otpCodeFrom('123-456', '', 6), '123456');
    });

    test('keeps the paste, not the half-typed digits it landed on', () {
      expect(otpCodeFrom('12123456', '12', 6), '123456');
    });

    test('ignores a digit typed past the end', () {
      expect(otpCodeFrom('1234567', '123456', 6), '123456');
    });

    test('follows the workflow code length', () {
      expect(otpCodeFrom('code 1234', '', 4), '1234');
      expect(otpCodeFrom('code 12345678', '', 8), '12345678');
    });
  });

  group('pastedCode', () {
    test('takes a code, however it was copied', () {
      expect(pastedCode('Your code is 123456', 6), '123456');
      expect(pastedCode('123 456', 6), '123456');
    });

    test('refuses what is not a code', () {
      expect(pastedCode('08031234567', 6), isNull);
      expect(pastedCode('hello', 6), isNull);
      expect(pastedCode('', 6), isNull);
    });
  });
}
