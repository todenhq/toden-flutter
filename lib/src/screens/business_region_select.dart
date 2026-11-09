import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/verification_provider.dart';
import '../services/api_service.dart';
import '../widgets/ui_select.dart';

// ─── The registry region, for split registers ────────────────────────────────
//
// The US, India, Canada and the UAE file companies per state or emirate, and
// the register is asked ONE region at a time, so a number alone does not name
// a company there. Shared by the name search and by registration-number entry
// when the workflow offers no search. Mirrors the web SDK's
// components/BusinessRegionField.tsx and the RN SDK's BusinessRegionField.

/// The country's registry regions; empty when it has a single register, and
/// also when the catalogue is unreachable ("do not ask" is the safe answer:
/// the register says so on its own).
Future<List<BusinessRegion>> loadBusinessRegions(
  WidgetRef ref,
  String country,
) async {
  if (country.isEmpty) return const [];
  try {
    final res = await ref
        .read(kYCNotifierProvider.notifier)
        .api
        .businessRegions(country);
    return res.regions;
  } catch (_) {
    return const [];
  }
}

class BusinessRegionSelect extends ConsumerWidget {
  final List<BusinessRegion> regions;

  const BusinessRegionSelect({super.key, required this.regions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (regions.isEmpty) return const SizedBox.shrink();
    final region =
        ref.watch(kYCNotifierProvider.select((s) => s.businessSubdivisionCode));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('State or region of registration', style: context.myazaText.label),
        const SizedBox(height: UiSpacing.sm),
        UiSelect<String>(
          value: (region ?? '').isEmpty ? null : region,
          sheetTitle: 'State or region',
          searchable: true,
          options: [
            for (final r in regions)
              UiSelectOption(value: r.code, label: r.name),
          ],
          onChanged: (code) => ref
              .read(kYCNotifierProvider.notifier)
              .setBusinessField('subdivisionCode', code),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
