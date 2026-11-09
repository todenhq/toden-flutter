import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/registration_hint.dart';
import '../config/theme.dart';
import '../services/api_business.dart';
import '../widgets/ui_alert.dart';
import 'business_number_fields.dart';
import 'business_picked_section.dart';
import 'business_region_select.dart';

// The first screen of the business step when there is no search by name
// (switched off, refused, or "enter the number"): the registration number is
// the whole question. The name is asked only when the workflow requires it;
// the register supplies it on Continue, which then fills the details screen.
// Mirrors the web and RN SDKs (lockstep).

class BusinessNumberEntry extends StatelessWidget {
  final String? notice;
  final List<BusinessRegion> regions;
  final BusinessProduct productDef;
  final RegistrationHint regHint;
  final bool numberValid;
  final bool formatOk;
  final bool requireName;
  final TextEditingController regCtrl;
  final TextEditingController nameCtrl;
  final String country;
  final String name;
  final bool isSandbox;
  final void Function(String key, String value) onChanged;

  const BusinessNumberEntry({
    super.key,
    required this.notice,
    required this.regions,
    required this.productDef,
    required this.regHint,
    required this.numberValid,
    required this.formatOk,
    required this.requireName,
    required this.regCtrl,
    required this.nameCtrl,
    required this.country,
    required this.name,
    required this.isSandbox,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final number = regCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          UiAlert(
            variant: UiAlertVariant.info,
            title: 'Enter the registration number',
            message: notice!,
          ),
          const SizedBox(height: UiSpacing.md),
        ],
        BusinessRegionSelect(regions: regions),
        BusinessNumberFields(
          productDef: productDef,
          regHint: regHint,
          numberValid: numberValid,
          formatOk: formatOk,
          showName: requireName,
          requireName: requireName,
          regCtrl: regCtrl,
          nameCtrl: nameCtrl,
          onChanged: onChanged,
        ),
        if (number.isNotEmpty) ...[
          const SizedBox(height: UiSpacing.md),
          BusinessPickedSection(
            country: country,
            name: name,
            registrationNumber: number,
            isSandbox: isSandbox,
            showCard: false,
            onChange: () => onChanged('registrationNumber', ''),
          ),
        ],
      ],
    );
  }
}
