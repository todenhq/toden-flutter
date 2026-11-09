import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/country_summary_select.dart';
import '../widgets/ui_input.dart';
import '../i18n/text_scope.dart';

// ─── Business-details field parts ─────────────────────────────────────────────
//
// The shared field label, the country of registration row and the key-people
// contact email, split out of
// business_details_screen.dart to keep that screen readable. The company
// profile section lives in business_company_info_fields.dart.

/// A field label with an "(optional)" or "*" suffix, matching the rest of the
/// flow's label styling.
class BusinessFieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const BusinessFieldLabel({
    super.key,
    required this.label,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Text.rich(TextSpan(children: [
      TextSpan(text: label, style: text.label),
      if (required)
        TextSpan(
          text: ' *',
          style: text.label.copyWith(color: UiColors.error),
        )
      else
        TextSpan(
          text: ' (optional)',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
    ]));
  }
}

/// Optional contact email used to send key-people (director/owner) verification
/// invites. Shown only when the workflow emails invites for a full-KYC role.
class BusinessContactEmailField extends StatelessWidget {
  final TextEditingController controller;
  final bool valid;
  final ValueChanged<String> onChanged;

  const BusinessContactEmailField({
    super.key,
    required this.controller,
    required this.valid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BusinessFieldLabel(label: context.verificationText('business.contactEmail.label')),
        const SizedBox(height: 2),
        Text(
          context.verificationText('business.contactEmail.hint'),
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: UiSpacing.xs),
        UiInput(
          controller: controller,
          hint: 'admin@company.com',
          keyboardType: TextInputType.emailAddress,
          errorText: valid ? null : 'Enter a valid email address.',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The country of registration, in the summary row the Proof of Address and
/// ID steps use (CountrySummarySelect). Mirrors the web SDK's
/// BusinessDetailsStep.
class BusinessCountryRow extends StatelessWidget {
  final List<String> countries;

  /// The current pick (empty shows the placeholder).
  final String country;

  /// The visitor's own country, pinned in the list as "Your location".
  final String? geoCountry;

  final ValueChanged<String> onPick;

  const BusinessCountryRow({
    super.key,
    required this.countries,
    required this.country,
    required this.onPick,
    this.geoCountry,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    return CountrySummarySelect(
      countries: countries,
      value: country.isEmpty ? null : country,
      label: t('business.details.countryCaption'),
      geoCountry: geoCountry,
      onPick: onPick,
      copy: CountrySummaryCopy(
        placeholder: t('business.country.placeholder'),
        change: t('business.country.change'),
        choose: t('business.country.choose'),
        search: t('business.country.searchPlaceholder'),
        noMatches: t('business.country.noMatch'),
        selected: t('business.country.selected'),
        yourLocation: t('business.details.countryPinnedLocation'),
      ),
    );
  }
}
