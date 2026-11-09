import '../config/scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../config/business_application.dart';
import '../i18n/text_scope.dart';
import '../providers/step_resubmit.dart';
import 'consent_legal_notice.dart';
import 'consent_copy.dart';
import 'consent_emblem.dart';
import 'consent_journey.dart';
import 'consent_process_steps.dart';
import '../providers/verification_provider.dart';
import '../widgets/ui_button.dart';
import '../widgets/icons/icons.dart';

// ─── Consent screen ───────────────────────────────────────────────────────────

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final config = ref.watch(verificationConfigProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final firstName = config.userData?.firstName ?? '';
    // The scope is read FIRST, whoever the workflow is about: a scoped
    // business workflow runs its scope's own steps, never the KYB application.
    final scope = configScope(config.scope);
    final isBusiness = isBusinessApplication(config.subjectType, config.scope);
    final scopedBusiness = isScopedBusiness(config.subjectType, config.scope);
    final faceScope = isFaceScope(scope);
    final business = config.business;

    // Every line is a catalogue text keyed by the screen's variant
    // (consent_copy.dart). An older consent.title/description (tokens filled)
    // wins over every variant, as it always did.
    final t = ref.watch(verificationTextProvider);
    final title = consentTitle(
      t,
      isBusiness: isBusiness,
      scope: scope,
      scopedBusiness: scopedBusiness,
      firstName: firstName,
      legacy: config.consent?.title,
    );

    // What this flow ACTUALLY does — the notice must not overclaim
    // (facial recognition with no selfie step) or underclaim (recording
    // video without saying so, which is the one that carries risk). A business
    // flow captures a face only when the applicant verifies their own identity
    // in-flow; a pure registry lookup captures nothing.
    final capturesFace = isBusiness
        ? hasApplicantVerification(business)
        : faceScope || (scope == null && config.enableSelfie);
    final recordsVideo = capturesFace ||
        (!isBusiness && scope == null && config.enableDocumentCapture);

    final steps = consentProcessSteps(config,
        isBusiness: isBusiness, scope: scope, t: t, scopedBusiness: scopedBusiness);
    // Calm copy, then how long the flow takes, from the steps it runs.
    final description = consentDescription(
      t,
      isBusiness: isBusiness,
      scope: scope,
      scopedBusiness: scopedBusiness,
      legacy: config.consent?.description,
      minutes: consentMinutes(steps),
    );

    // A reviewer sent this applicant back. Say so, and say why — the note is
    // the only thing on screen that explains a flow which has silently lost
    // most of its steps. Above the hero so it is read before the instructions.
    final redoNote = resubmitNote(config.resubmit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: UiSpacing.sm),

        if (redoNote != null) ...[
          Container(
            padding: const EdgeInsets.all(UiSpacing.md),
            decoration: BoxDecoration(
              color: colors.warningBg,
              borderRadius: BorderRadius.circular(UiRadius.lg),
              border: Border.all(
                color: UiColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const UiIcon(UiIcons.refreshCw, size: 16, color: UiColors.warning),
                const SizedBox(width: UiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('welcome.redo.title'),
                        style: text.bodyMedium.copyWith(color: UiColors.warning),
                      ),
                      const SizedBox(height: 2),
                      Text(redoNote, style: text.bodySmall.copyWith(color: colors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: UiSpacing.lg),
        ],

        // ── The mark, the title, the description ───────────────────────────
        const Center(child: ConsentEmblem()),
        const SizedBox(height: UiSpacing.md),
        Text(
          title,
          style: text.heading1.copyWith(fontWeight: FontWeight.w600, height: 1.25),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: UiSpacing.sm),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              description,
              style: text.bodyMedium.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: UiSpacing.lg),

        // ── What the flow will do ────────────────────────────────────────────
        ConsentJourney(heading: t('welcome.process.heading'), steps: steps),
        const SizedBox(height: UiSpacing.lg),

        // ── Consent notice ───────────────────────────────────────────────────
        // Consent is given by ACTING now, so the notice sits immediately above
        // the button it describes — adjacency is what makes it informed. The
        // biometric sentence is DERIVED: claiming facial recognition on a flow
        // with no selfie step would be false, and recording video without
        // saying so is the failure that actually matters.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(UiRadius.sm),
          ),
          child: ConsentLegalNotice(
            // A scoped business workflow processes business data too.
            isBusiness: isBusiness || scopedBusiness,
            capturesFace: capturesFace,
            recordsVideo: recordsVideo,
          ),
        ),
        const SizedBox(height: UiSpacing.md),

        // ── Continue ─────────────────────────────────────────────────────────
        UiButton(
          label: t('common.continue'),
          onPressed: notifier.nextStep,
        ),
        const SizedBox(height: UiSpacing.sm),

        // ── Reassurance footer ───────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiIcon(UiIcons.lock, size: 13, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(t('welcome.secureNote'), style: text.bodySmall),
          ],
        ),
      ],
    );
  }
}
