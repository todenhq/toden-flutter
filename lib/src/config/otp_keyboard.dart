import 'package:flutter/services.dart';

import 'otp_code.dart';

// ─── OTP keyboard ─────────────────────────────────────────────────────────────
//
// The keyboard a code field asks for. Digits only (the default) keeps the
// number keyboard and the platform defaults, exactly as before. An alphanumeric
// code (the workflow's `alphanumericCode`) needs letters: a text keyboard,
// capitalising, no autocorrect (it would rewrite a code into a word), and a
// formatter that keeps letters and digits and upper-cases them. Mirrors the web
// SDK's codeFieldProps and the React Native SDK's lib/otp-keyboard.ts.

class OtpKeyboard {
  final TextInputType type;
  final TextCapitalization capitalization;
  final bool autocorrect;

  /// Null for digits: the field filters nothing as it is typed, so a pasted
  /// sentence reaches otpCodeFrom whole.
  final List<TextInputFormatter>? formatters;

  const OtpKeyboard._(
      this.type, this.capitalization, this.autocorrect, this.formatters);

  factory OtpKeyboard.of({required bool alphanumeric, required int length}) =>
      alphanumeric
          ? OtpKeyboard._(TextInputType.text, TextCapitalization.characters,
              false, [OtpCodeFormatter(length)])
          : const OtpKeyboard._(
              TextInputType.number, TextCapitalization.none, true, null);
}

/// Keeps letters and digits, upper-cased and cut to [length]. It reads the
/// edit through otpCodeFrom rather than dropping characters one by one, so
/// "Your code is K7MP2Q" pasted whole still lands as K7MP2Q.
class OtpCodeFormatter extends TextInputFormatter {
  final int length;

  OtpCodeFormatter(this.length);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final next =
        otpCodeFrom(newValue.text, oldValue.text, length, alphanumeric: true);
    if (next == newValue.text) return newValue;
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
}
