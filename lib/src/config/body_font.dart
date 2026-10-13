import 'package:flutter/painting.dart';

/// The SDK's two bundled typefaces. Geist is for small text and anything typed
/// into a field; Bricolage Grotesque is for headings and text at 16px and up
/// (see `config/theme.dart`).
///
/// Geist is BUNDLED with the package (pubspec `fonts:`), not fetched through
/// google_fonts: that package does not carry the family, and a bundled face is
/// there on the first frame with no network request.
const String kBodyFontFamily = 'Geist';

/// This package's name, which is how Flutter addresses a font a package ships.
const String kBodyFontPackage = 'myaza_kyc_sdk_flutter';

/// The weights bundled for [kBodyFontFamily]. A text style asking for another
/// weight gets the nearest of these, so add a file to pubspec before using one.
const List<int> kBodyFontWeights = [400, 500, 600, 700];

/// [base] set in the bundled body face.
TextStyle bodyFont(TextStyle base) =>
    base.copyWith(fontFamily: kBodyFontFamily, package: kBodyFontPackage);

/// The heading typeface, also used for text at 16px and up. BUNDLED like Geist,
/// so it never waits on a network request: it used to be fetched from Google's
/// font servers at first launch, which showed a fallback face first and left
/// the flow in the system font with no connection.
const String kHeadingFontFamily = 'BricolageGrotesque';

/// The weights bundled for [kHeadingFontFamily].
const List<int> kHeadingFontWeights = [400, 500, 600, 700];

/// [base] set in the bundled heading face.
TextStyle headingFont(TextStyle base) =>
    base.copyWith(fontFamily: kHeadingFontFamily, package: kBodyFontPackage);
