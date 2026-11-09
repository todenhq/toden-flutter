import 'package:flutter/material.dart';

import '../config/id_types.dart' show IdTypeConfig;
import '../config/immersive_layout.dart';
import '../config/theme.dart';
import 'country_flag.dart';
import 'immersive_glass.dart';

// ─── Document info pill ───────────────────────────────────────────────────────
//
// Says WHICH document is expected, in frame.
//
// Going full-screen took away the sheet header and the "Required: …" pill that
// used to carry this, and the camera is precisely where it matters: it is the
// last point before the shutter where someone can notice they have picked up
// the wrong document, or the right document from the wrong country.

/// The document's name, short enough to sit in a pill.
///
/// The catalogue label is written for a picker, where "International Passport"
/// disambiguates. Beside a flag it is redundant twice over — the country is
/// already shown, and nobody is choosing anything at this point. Keyed off the
/// ID type rather than trimmed from the string, so it holds for every country's
/// passport whatever its catalogue label says.
/// Without an ID type, [fallback] (the step's own label) is used as it is.
String shortDocumentLabel(IdTypeConfig? idType, [String fallback = '']) =>
    idType == null
        ? fallback
        : idType.key == 'passport'
            ? 'Passport'
            : idType.label;

/// Flag + document name on the full-screen camera's glass, so the person can
/// see WHICH document is expected. Centred in the top bar, and the item that
/// gives way on a narrow phone: its label truncates past the width it is given.
/// The React Native SDK's DocumentPill.
class DocumentInfoPill extends StatelessWidget {
  /// The document's name, already short ([shortDocumentLabel]).
  final String label;

  /// ISO-3166 alpha-2 of the document's country (the effective one in a
  /// multi-region flow).
  final String? country;

  const DocumentInfoPill({super.key, required this.label, this.country});

  @override
  Widget build(BuildContext context) {
    final code = country;
    return Container(
      height: kImmersiveTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ImmersiveGlass.fill,
        borderRadius: BorderRadius.circular(UiRadius.full),
        border: Border.all(color: ImmersiveGlass.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The flag carries the country on its own: a name beside it is the
          // same fact twice, and the flag reads faster at a glance than text.
          if (code != null && code.isNotEmpty) ...[
            UiCountryFlag(country: code, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ImmersiveGlass.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
