import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/nfc_intro.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../presence/presence_background_allow_steps.dart' show AllowSteps;
import '../widgets/background_ask_parts.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_button.dart';

/// The glyph for each row of the intro.
const _icons = {
  NfcIntroIcon.camera: UiIcons.camera,
  NfcIntroIcon.passport: UiIcons.bookUser,
  NfcIntroIcon.card: UiIcons.idCard,
  NfcIntroIcon.phone: UiIcons.smartphone,
  NfcIntroIcon.hold: UiIcons.timer,
};

/// What the chip read is and how to hold the document, before anything
/// starts. Laid out as the address-monitoring explanation is
/// (background_ask_screen.dart, from the same parts): the hero, a title, the
/// steps as one grouped card and the "before you start" card over the button.
/// The read used to start on arrival, which only worked for people who already
/// knew a passport's chip is in its cover. Continue starts it (or the
/// photo-page scan, when the code that unlocks the chip is still needed).
class NfcIntroView extends StatelessWidget {
  const NfcIntroView({
    super.key,
    required this.passport,
    required this.needsCode,
    required this.onContinue,
    this.platform,
  });

  final bool passport;
  final bool needsCode;
  final VoidCallback onContinue;

  /// Overrides the running platform (tests).
  final NfcIntroPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final copy = nfcIntroCopy(
      passport: passport,
      needsCode: needsCode,
      platform: platform ??
          (Platform.isIOS
              ? NfcIntroPlatform.ios
              : Platform.isAndroid
                  ? NfcIntroPlatform.android
                  : NfcIntroPlatform.other),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: UiSpacing.md),
            const AskHero(icon: UiIcons.nfc).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: UiSpacing.md),
            Semantics(
              header: true,
              child: Text(copy.title, style: text.heading2),
            ),
            const SizedBox(height: UiSpacing.xs),
            Text(
              copy.description,
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: UiSpacing.lg),
            AskReasons(
              reasons: [
                for (final row in copy.rows)
                  AskReason(_icons[row.icon]!, row.title, row.caption,
                      done: row.done),
              ],
            ),
            const SizedBox(height: UiSpacing.lg),
            AskNextStep(
              steps: AllowSteps(lead: copy.beforeLead, tap: copy.beforeTap),
            ),
          ],
        ).animate(delay: 120.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: UiSpacing.lg),
        UiButton(
          label: context.verificationText('common.continue'),
          onPressed: onContinue,
        ),
      ],
    );
  }
}
