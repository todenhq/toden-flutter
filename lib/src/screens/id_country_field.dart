import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/text_scope.dart';
import '../providers/verification_provider.dart';
import '../widgets/country_summary_select.dart';

// ─── The ID's country, on the ID-type step ────────────────────────────────────
//
// The country that issued the ID, at the top of the ID-type step: the
// `combined` layout (config/id_selection_layout.dart), in the summary row the
// Proof of Address step uses. Changing it swaps the ID list beneath, as the
// country step would have. Mirrors the web SDK's steps/IdCountryField.
//
// It opens holding an answer rather than an empty field, since the list under
// it needs a country to show anything: the workflow's own country when it is
// on offer, else the visitor's, else the first offered. That pick is marked
// automatic (setCountryAuto), as an IP guess is elsewhere.

/// The country the field opens on, from [options].
String? initialIdCountry(List<String> options, {String? configured, String? geo}) {
  for (final code in [configured?.toUpperCase(), geo?.toUpperCase()]) {
    if (code != null && options.contains(code)) return code;
  }
  return options.isEmpty ? null : options.first;
}

class IdCountryField extends ConsumerStatefulWidget {
  /// ISO-2 codes on offer (upper case).
  final List<String> options;

  const IdCountryField({super.key, required this.options});

  @override
  ConsumerState<IdCountryField> createState() => _IdCountryFieldState();
}

class _IdCountryFieldState extends ConsumerState<IdCountryField> {
  String? get _initial => initialIdCountry(
        widget.options,
        configured: ref.read(verificationConfigProvider).country,
        geo: ref.read(kYCNotifierProvider).serverConfig.geoCountry,
      );

  @override
  void initState() {
    super.initState();
    // After the first frame: a provider may not be written during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initial = _initial;
      if (ref.read(kYCNotifierProvider).selectedCountry == null && initial != null) {
        ref.read(kYCNotifierProvider.notifier).setCountryAuto(initial);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    final state = ref.watch(kYCNotifierProvider);
    return CountrySummarySelect(
      countries: widget.options,
      value: state.selectedCountry?.toUpperCase() ?? _initial,
      label: t('selectDocument.country.label'),
      geoCountry: state.serverConfig.geoCountry,
      onPick: (code) {
        if (code != state.selectedCountry) {
          ref.read(kYCNotifierProvider.notifier).setCountry(code);
        }
      },
      copy: CountrySummaryCopy(
        placeholder: t('selectDocument.country.placeholder'),
        change: t('selectDocument.country.change'),
        choose: t('selectDocument.country.choose'),
        search: t('selectDocument.country.search'),
        noMatches: t('selectDocument.country.noResults'),
        selected: t('selectDocument.country.selected'),
        yourLocation: t('selectDocument.country.yourLocation'),
      ),
    );
  }
}
