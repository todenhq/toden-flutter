import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import '../config/verification_config.dart';
import '../config/session_cancelled.dart';
import '../config/session_declined.dart';
import '../i18n/translate.dart' show defaultTextFn;
import '../widgets/ui_alert.dart';
import '../widgets/ui_button.dart';
import '../widgets/icons/icons.dart';

// ─── Error view ───────────────────────────────────────────────────────────────

class ErrorView extends StatelessWidget {
  final VerificationError error;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  /// Back to the step that can fix the refusal (submit_recovery.dart). When
  /// present it is the primary action: the application is not lost, only
  /// incomplete, and closing would throw it away.
  final VoidCallback? onGoBack;

  const ErrorView({super.key,
    required this.error,
    required this.onClose,
    this.onRetry,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final title = switch (error.code) {
      'insufficient_credits' => 'Credits Exhausted',
      'invalid_api_key' => 'Authentication Failed',
      'feature_disabled' => 'Verification Unavailable',
      'invalid_workflow' => 'Verification Unavailable',
      'upload_failed' => 'Upload Failed',
      'network_error' => 'Connection Failed',
      'invalid_state' => 'Submission Incomplete',
      // Normally the dedicated cancelled screen takes over first; this keeps
      // any path that still lands here from reading as a failed submission.
      kSessionCancelledCode => kSessionCancelledTitle,
      kSessionDeclinedCode => defaultTextFn(kSessionEndedTitleKey),
      _ => 'Submission Failed',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: UiSpacing.xl),
            Center(
              child: _ErrorBadge(colors: colors)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 450.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: UiSpacing.lg),
            Text(
              title,
              style: text.heading1,
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: UiSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpacing.md),
              child: UiAlert(
                variant: UiAlertVariant.error,
                title: 'What happened',
                message: error.message,
              ),
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
          ],
        ),
        Row(
          children: [
            if (onRetry != null) ...[
              Expanded(
                child: UiButton.outline(
                  label: 'Try Again',
                  onPressed: onRetry,
                  leadingIcon: const UiIcon(UiIcons.refreshCw),
                ),
              ),
              const SizedBox(width: UiSpacing.md),
            ],
            if (onGoBack != null) ...[
              Expanded(
                child: UiButton.outline(label: 'Close', onPressed: onClose),
              ),
              const SizedBox(width: UiSpacing.md),
              Expanded(
                child: UiButton(
                  label: 'Go back',
                  onPressed: onGoBack,
                  leadingIcon: const UiIcon(UiIcons.arrowLeft),
                ),
              ),
            ] else
              Expanded(
                child: UiButton(label: 'Close', onPressed: onClose),
              ),
          ],
        )
            .animate(delay: 420.ms)
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, end: 0, duration: 300.ms),
      ],
    );
  }
}

// ─── Check badge ──────────────────────────────────────────────────────────────
class _ErrorBadge extends StatelessWidget {
  final UiColorScheme colors;

  const _ErrorBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.errorBg,
        border: Border.all(
          color: UiColors.error.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const UiIcon(
        UiIcons.circleAlert,
        size: 44,
        color: UiColors.error,
      ),
    );
  }
}
