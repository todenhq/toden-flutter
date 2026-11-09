import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/registration_hint.dart';
import '../config/theme.dart';
import '../widgets/ui_input.dart';
import 'business_details_parts.dart';
import '../i18n/text_scope.dart';

// The registration number and the registered name. Shared by the first screen
// of the business step (when the number IS the question: search off, refused
// or "enter the number") and the second, where the register's answer is
// confirmed. Mirrors the web and RN SDKs.

class BusinessNumberFields extends StatelessWidget {
  final BusinessProduct productDef;
  final RegistrationHint regHint;
  final bool numberValid;
  final bool formatOk;
  final bool showName;
  final bool requireName;
  final TextEditingController regCtrl;
  final TextEditingController nameCtrl;
  final void Function(String key, String value) onChanged;

  const BusinessNumberFields({
    super.key,
    required this.productDef,
    required this.regHint,
    required this.numberValid,
    required this.formatOk,
    required this.showName,
    required this.requireName,
    required this.regCtrl,
    required this.nameCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live like the web SDK: a wrong CAC prefix is corrected on the spot,
        // not discovered on Continue. The registry tip fills the same slot
        // until there is an error to show.
        UiInput(
          label: productDef.input == BusinessProductInput.tin
              ? productDef.inputLabel
              : context.verificationText('business.details.registrationNumberLabel'),
          controller: regCtrl,
          hint: regHint.placeholder,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          errorText: regCtrl.text.trim().isNotEmpty && !numberValid
              ? (!formatOk && regHint.formatError != null
                  ? regHint.formatError
                  : 'Enter a valid ${productDef.inputLabel.toLowerCase()}.')
              : null,
          helperText: regHint.tip,
          onChanged: (v) => onChanged('registrationNumber', v),
        ),
        if (showName) ...[
          const SizedBox(height: UiSpacing.md),
          BusinessFieldLabel(
            label: context.verificationText('business.details.nameLabel'),
            required: requireName,
          ),
          const SizedBox(height: UiSpacing.xs),
          UiInput(
            controller: nameCtrl,
            hint: 'Enter the registered business name',
            autocorrect: false,
            onChanged: (v) => onChanged('registrationName', v),
          ),
        ],
      ],
    );
  }
}
