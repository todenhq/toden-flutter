import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/ui_button.dart';
import '../widgets/icons/icons.dart';
import '../i18n/business_variants.dart';
import '../i18n/text_scope.dart';

// ─── Contact verification — footer actions ────────────────────────────────────
//
// The error line, the primary submit button, and the optional skip. Lifted out
// of ContactVerificationScreen when the delivery-channel picker joined it, to
// keep that file inside the 200-line limit.

class ContactActions extends StatelessWidget {
  /// Null when there is nothing to report.
  final String? error;

  /// Send-the-code vs verify-the-code: changes only the label and the handler.
  final bool hasChallenge;
  final bool isBusy;

  /// Null disables the button (invalid input, or a request in flight).
  final VoidCallback? onSubmit;

  /// Shown only for an optional step.
  final VoidCallback? onSkip;

  /// Drives the closing reassurance line, which differs per channel.
  final bool isPhone;

  const ContactActions({
    super.key,
    required this.error,
    required this.hasChallenge,
    required this.isBusy,
    required this.onSubmit,
    required this.onSkip,
    required this.isPhone,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final t = context.verificationText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          const SizedBox(height: UiSpacing.sm),
          Text(error!,
              style: text.bodySmall.copyWith(color: UiColors.error)),
        ],
        const SizedBox(height: UiSpacing.xl),
        UiButton(
          label: t(hasChallenge ? 'contact.verifyCode' : 'contact.sendCode'),
          isLoading: isBusy,
          onPressed: onSubmit,
        ),
        if (onSkip != null) ...[
          const SizedBox(height: UiSpacing.sm),
          Center(
            child: TextButton(
              onPressed: isBusy ? null : onSkip,
              child: Text(t('contact.skip'),
                  style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            ),
          ),
        ],
        const SizedBox(height: UiSpacing.md),
        // Answers the question the step provokes: an email step is asked "what
        // will you do with my address", a phone step "will this cost me money".
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiIcon(
              isPhone ? UiIcons.smartphone : UiIcons.mail,
              size: 12,
              color: colors.textSecondary,
            ),
            const SizedBox(width: UiSpacing.xs),
            Flexible(
              child: Text(
                t(isPhone
                    ? 'contact.phone.footer'
                    : businessKey('contact.email.footer', context.scopedBusinessFlow)),
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
