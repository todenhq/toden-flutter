// ─── A file name worth showing the applicant ─────────────────────────────────
//
// Phone cameras and some pickers name a photo with a random id
// ("940f84e9-18c6-4894-accc-3621f5b1….jpg"), which reads as noise beside a
// document; callers show "Uploaded" (or the group's title) instead. Ordinary
// names, including the camera's own "IMG_1234.jpg", are kept.
//
// MIRRORS the web SDK's lib/display-file-name.ts. Keep the two in step.

final _randomId = RegExp(
    r'^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$',
    caseSensitive: false);
final _longHex = RegExp(r'^[0-9a-f]{24,}$', caseSensitive: false);
final _extension = RegExp(r'\.[a-z0-9]{1,5}$', caseSensitive: false);

/// [name] trimmed, or null when it is empty or machine-made.
String? displayFileName(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final base = trimmed.replaceFirst(_extension, '');
  if (base.isEmpty || _randomId.hasMatch(base) || _longHex.hasMatch(base)) {
    return null;
  }
  return trimmed;
}
