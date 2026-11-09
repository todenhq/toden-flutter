import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import '../config/verification_config.dart';
import '../i18n/text_scope.dart';
import '../presence/background_ask_controller.dart';
import '../presence/background_presence.dart' show AllowNext;
import '../presence/presence_background_allow_steps.dart';
import '../presence/presence_background_primer.dart';
import '../presence/presence_status.dart' show openLocationSettings;
import '../widgets/background_ask_parts.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_button.dart';

/// The workflow's presence policy, as the primer's numbers read it.
PresencePolicyNumbers presencePolicyOf(VerificationConfig config) {
  final a = config.addressCollection;
  return PresencePolicyNumbers(
    windowDays: a?.presenceWindowDays,
    minNights: a?.presenceMinNights,
    minDays: a?.presenceMinDays,
  );
}

/// The "allow all the time" screen.
///
/// Shown once, right after a flow with presence monitoring is submitted and
/// immediately before the OS prompt, because that prompt is roughly a one-time
/// chance (presence_background_primer.dart). It gives the person THEIR
/// reasons, each one true of how the check works: less effort (the count is
/// the real one for this workflow's policy, at the server's weighting), done
/// sooner, and only this address. "Not now" still finishes the flow; the
/// success card then offers the switch again. Mirrors the React Native SDK's
/// screens/SubmittedBackgroundAsk.tsx.
class BackgroundAskScreen extends StatefulWidget {
  const BackgroundAskScreen({
    super.key,
    required this.config,
    required this.controller,
    required this.onDone,
  });

  final VerificationConfig config;
  final BackgroundAskController controller;

  /// The person answered (either way): on to the success screen.
  final VoidCallback onDone;

  @override
  State<BackgroundAskScreen> createState() => _BackgroundAskScreenState();
}

class _BackgroundAskScreenState extends State<BackgroundAskScreen> {
  bool _busy = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    // The permission arrived while Settings was on offer: nothing left to ask.
    if (!widget.controller.settingsOffer &&
        widget.controller.outcome == BackgroundOutcome.on) {
      _finish();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    var next = AllowNext.off;
    try {
      next = await widget.controller.allow();
    } finally {
      if (mounted) setState(() => _busy = false);
      if (next == AllowNext.off) _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    final text = context.myazaText;
    final colors = context.myazaColors;
    final business = widget.config.subjectType == 'business';
    final policy = presencePolicyOf(widget.config);
    final effort = effortWithoutBackground(policy, isBusiness: business);
    final reasons = [
      AskReason(UiIcons.check, 'Nothing more to do', effortSentence(effort, isBusiness: business)),
      AskReason(UiIcons.timer, 'Done sooner', withinSentence(policy.windowDays)),
      AskReason(
        UiIcons.shieldCheck,
        'Only this address',
        business
            ? 'We only check whether your phone is at the premises. We never see where else you go.'
            : 'We only check whether your phone is at this address. We never see where else you go.',
      ),
    ];
    final offer = widget.controller.settingsOffer;
    final steps = offer
        ? backgroundSettingsSteps(isIOS: Platform.isIOS)
        : backgroundAllowSteps(
            isIOS: Platform.isIOS,
            androidApi: widget.controller.androidApi,
            foregroundGranted: widget.controller.foregroundGranted,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: UiSpacing.md),
                const AskHero().animate().fadeIn(duration: 300.ms),
                const SizedBox(height: UiSpacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    t(business ? 'address.background.title.business' : 'address.background.title'),
                    style: text.heading2,
                  ),
                ),
                const SizedBox(height: UiSpacing.xs),
                Text(
                  t(business ? 'address.background.description.business' : 'address.background.description'),
                  style: text.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: UiSpacing.lg),
                AskReasons(reasons: reasons),
                const SizedBox(height: UiSpacing.lg),
                AskNextStep(steps: steps),
              ],
            ).animate(delay: 120.ms).fadeIn(duration: 350.ms),
          ),
        ),
        const SizedBox(height: UiSpacing.md),
        if (offer)
          const UiButton(label: 'Open Settings', onPressed: openLocationSettings)
        else
          UiButton(
            label: t('address.background.allow'),
            isLoading: _busy,
            onPressed: _busy ? null : _allow,
          ),
        const SizedBox(height: UiSpacing.xs),
        UiButton(
          label: t('address.background.later'),
          variant: UiButtonVariant.ghost,
          labelColor: colors.textSecondary,
          onPressed: _busy
              ? null
              : () {
                  widget.controller.later();
                  _finish();
                },
        ),
      ],
    );
  }
}
