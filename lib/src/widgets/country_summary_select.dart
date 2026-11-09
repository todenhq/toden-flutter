import 'package:flutter/material.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'country_flag.dart';
import 'dial_code_picker.dart' show CountryPickerCopy, showCountryPicker;
import 'icons/icons.dart';

// ─── Country summary select ───────────────────────────────────────────────────
//
// A country, picked from a summary row: a 40px round flag, a small caption
// over the country's name, and a Change pill. Used where the country is
// usually settled and only sometimes changed: the Proof of Address step, the
// combined ID step and the business Country of registration. Mirrors the web
// SDK's components/CountrySummarySelect and the RN twin.
//
// The list is THE country sheet (showCountryPicker), region-grouped and
// searchable, with the current answer ("Selected") and the visitor's own
// country ("Your location") pinned above the regions.
//
// One country on offer, or a locked answer, is a settled fact: the row
// without the pill, and nothing to tap.

/// The words the row and its sheet show, from the caller's own text group.
class CountrySummaryCopy {
  final String placeholder;
  final String change;
  final String choose;
  final String search;
  final String noMatches;
  final String selected;
  final String yourLocation;

  const CountrySummaryCopy({
    required this.placeholder,
    required this.change,
    required this.choose,
    required this.search,
    required this.noMatches,
    required this.selected,
    required this.yourLocation,
  });
}

/// The flag's diameter, the size the web row draws (h-10 w-10).
const double kCountrySummaryFlagSize = 40;

class CountrySummarySelect extends StatelessWidget {
  /// ISO-2 codes on offer.
  final List<String> countries;

  /// The current answer (null shows the placeholder).
  final String? value;

  final ValueChanged<String> onPick;

  /// The caption over the country: "Your address is in".
  final String label;

  /// The visitor's own country, from their IP, pinned when on offer.
  final String? geoCountry;

  final CountrySummaryCopy copy;

  /// Settled and not to be changed (a register that has answered).
  final bool disabled;

  const CountrySummarySelect({
    super.key,
    required this.countries,
    required this.value,
    required this.onPick,
    required this.label,
    required this.copy,
    this.geoCountry,
    this.disabled = false,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showCountryPicker(
      context,
      value,
      codes: countries,
      pinned: geoCountry?.toUpperCase(),
      grouped: true,
      // The caption names what is being picked: "Your ID was issued in".
      title: label,
      copy: CountryPickerCopy(
        search: copy.search,
        noMatches: copy.noMatches,
        selected: copy.selected,
        yourLocation: copy.yourLocation,
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final settled = countries.length == 1 || (disabled && value != null);
    final shown = settled ? (disabled && value != null ? value! : countries.first) : value;
    final radius = BorderRadius.circular(UiRadius.md);

    // 16 above and below the 40px flag: the height of the ID cards under it
    // (16 + 40 + 16 and the border), so the two stack as one list.
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Row(
        children: [
          _Flag(country: shown),
          const SizedBox(width: 12),
          Expanded(child: _Caption(label: label, name: shown, placeholder: copy.placeholder)),
          if (!settled) ...[
            const SizedBox(width: UiSpacing.sm),
            _ChangePill(label: shown != null ? copy.change : copy.choose),
          ],
        ],
      ),
    );

    final decoration = BoxDecoration(
      color: settled && disabled ? colors.backgroundSecondary : colors.background,
      borderRadius: radius,
      border: Border.all(color: colors.border),
    );

    if (settled) {
      return Semantics(
        label: '$label: ${countryLabel(shown!)}',
        excludeSemantics: true,
        child: DecoratedBox(decoration: decoration, child: body),
      );
    }

    return Semantics(
      button: true,
      label: '$label: ${shown != null ? countryLabel(shown) : copy.placeholder}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            splashColor: colors.primary.withValues(alpha: 0.06),
            highlightColor: colors.primary.withValues(alpha: 0.04),
            onTap: () => _open(context),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The round flag, ringed in the background colour, or a map pin while there
/// is no country yet.
class _Flag extends StatelessWidget {
  final String? country;
  const _Flag({required this.country});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    if (country == null) {
      return Container(
        width: kCountrySummaryFlagSize,
        height: kCountrySummaryFlagSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.backgroundSecondary, shape: BoxShape.circle),
        child: UiIcon(UiIcons.mapPin, size: 16, color: colors.textSecondary),
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.background, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: UiCountryFlag(country: country, size: kCountrySummaryFlagSize - 4),
    );
  }
}

/// The caption over the country's name (or the placeholder, muted).
class _Caption extends StatelessWidget {
  final String label;
  final String? name;
  final String placeholder;
  const _Caption({required this.label, required this.name, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final hasName = name != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall.copyWith(color: colors.textSecondary, height: 1.33),
        ),
        Text(
          hasName ? countryLabel(name!) : placeholder,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // The web's text-[15px]: off the type scale, so it keeps the copy
          // face, which [body] carries.
          style: text.body.copyWith(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: hasName ? FontWeight.w600 : FontWeight.w500,
            color: hasName ? colors.textDark : colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// "Change" (or "Choose" with nothing picked) and a chevron, in a primary tint.
class _ChangePill extends StatelessWidget {
  final String label;
  const _ChangePill({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: text.body.copyWith(
              fontSize: 12,
              height: 16 / 12,
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          UiIcon(UiIcons.chevronDown, size: 14, color: colors.primary),
        ],
      ),
    );
  }
}
