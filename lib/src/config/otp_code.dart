// Reading a code out of what landed in the code field. A MIRROR of the web and
// React Native SDKs' lib/otp-code.ts; change the three together.
//
// Two alphabets. Digits only, the default, is unchanged. An ALPHANUMERIC code
// (the workflow's `alphanumericCode`) keeps any ASCII letter or digit,
// upper-cased: the server sends from 23456789ABCDEFGHJKMNPQRSTUVWXYZ but
// sandbox still sends all zeros, and it compares without regard to case.

/// A run of exactly [length] digits standing on its own: "Your code is 123456".
String? _standaloneCode(String text, int length) {
  for (final part in text.split(RegExp(r'\D+'))) {
    if (part.length == length) return part;
  }
  return null;
}

final _capitalsAndDigits = RegExp(r'^[A-Z0-9]+$');
final _aDigit = RegExp(r'\d');

/// An alphanumeric code standing on its own in a message. Codes are sent in
/// capitals, so a word with a lower-case letter ("Your", "code") is not one; a
/// run with a digit beats one without ("CODE: K7MP" at length 4).
String? _standaloneAlphanumeric(String text, int length) {
  final runs = text
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.length == length && _capitalsAndDigits.hasMatch(part))
      .toList();
  for (final part in runs) {
    if (_aDigit.hasMatch(part)) return part;
  }
  return runs.isEmpty ? null : runs.first;
}

String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

String _alphanumerics(String text) =>
    text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// The code in the field after an edit. [previous] tells typing from a paste: a
/// paste over a half-typed code keeps what was pasted, not what was there.
String otpCodeFrom(String raw, String previous, int length,
    {bool alphanumeric = false}) {
  final code = alphanumeric
      ? _standaloneAlphanumeric(raw, length)
      : _standaloneCode(raw, length);
  if (code != null) return code;
  final kept = alphanumeric ? _alphanumerics(raw) : _digits(raw);
  if (kept.length <= length) return kept;
  return raw.length - previous.length > 1
      ? kept.substring(kept.length - length)
      : kept.substring(0, length);
}

/// The code on the clipboard, or null when there isn't one. Stricter than
/// typing: a phone number or an order reference must not fill the boxes.
String? pastedCode(String text, int length, {bool alphanumeric = false}) {
  final code = alphanumeric
      ? _standaloneAlphanumeric(text, length)
      : _standaloneCode(text, length);
  if (code != null) return code;
  final kept = alphanumeric ? _alphanumerics(text) : _digits(text);
  return kept.length == length ? kept : null;
}
