// Reading a code out of what landed in the code field. A MIRROR of the web and
// React Native SDKs' lib/otp-code.ts; change the three together.

/// A run of exactly [length] digits standing on its own: "Your code is 123456".
String? _standaloneCode(String text, int length) {
  for (final part in text.split(RegExp(r'\D+'))) {
    if (part.length == length) return part;
  }
  return null;
}

String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

/// The code in the field after an edit. [previous] tells typing from a paste: a
/// paste over a half-typed code keeps what was pasted, not what was there.
String otpCodeFrom(String raw, String previous, int length) {
  final code = _standaloneCode(raw, length);
  if (code != null) return code;
  final digits = _digits(raw);
  if (digits.length <= length) return digits;
  return raw.length - previous.length > 1
      ? digits.substring(digits.length - length)
      : digits.substring(0, length);
}

/// The code on the clipboard, or null when there isn't one. Stricter than
/// typing: a phone number or an order reference must not fill the boxes.
String? pastedCode(String text, int length) {
  final code = _standaloneCode(text, length);
  if (code != null) return code;
  final digits = _digits(text);
  return digits.length == length ? digits : null;
}
