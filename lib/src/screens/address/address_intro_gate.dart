import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../config/theme.dart';
import '../../widgets/ui_button.dart';
import '../../widgets/presence_milestone_track.dart';
import '../../widgets/presence_milestones.dart';
import 'address_intro_disclosures.dart';
import '../../widgets/icons/icons.dart';
import '../../i18n/text_scope.dart';
import '../../i18n/translate.dart' show TextFn;

// ─── The presence primer ─────────────────────────────────────────────────────
//
// Shown ONCE, on the address flow's first step, when the workflow verifies
// presence. It replaces that step's body until acknowledged — but the step's
// mount work still runs behind it, so the GPS is warm by the time "Continue" is
// tapped and the pin lands with no hesitation.
//
// Drawn in the SUCCESS CARD's language (the eyebrow badge, the milestone
// track, the header band) so the promise made here and the "address check
// active" card at the end read as two frames of one story. Mirrors the web and
// RN SDKs' AddressIntroGate — keep the copy in lockstep.

// The second milestone's caption depends on which tier the org runs. With
// background geofencing on, the "allow all the time" prompt is coming, and it
// is said ONCE, up front, beside the education. All catalogue texts.

class AddressIntroGate extends StatelessWidget {
  final VoidCallback onAcknowledge;

  /// The workflow opts into OS geofencing: the copy names the always prompt.
  final bool background;

  const AddressIntroGate({
    super.key,
    required this.onAcknowledge,
    this.background = false,
  });

  List<PresenceMilestone> _milestones(TextFn t) => [
        PresenceMilestone(
          icon: UiIcons.mapPinHouse,
          stage: t('address.intro.step1.stage'),
          title: t('address.intro.step1.title'),
          caption: t('address.intro.step1.caption'),
          active: true,
        ),
        PresenceMilestone(
          icon: UiIcons.radar,
          stage: t('address.intro.step2.stage'),
          title: t('address.intro.step2.title'),
          caption: t(background
              ? 'address.intro.step2.caption.background'
              : 'address.intro.step2.caption'),
        ),
        PresenceMilestone(
          icon: UiIcons.bellRing,
          stage: t('address.intro.step3.stage'),
          title: t('address.intro.step3.title'),
          caption: t('address.intro.step3.caption'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final t = context.verificationText;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PresenceCard(
            header: PresenceHeaderBand(
              badge: PresenceBadge(
                leading: UiIcon(UiIcons.mapPinCheck,
                    size: 12, color: colors.primary),
                label: t('address.intro.badge'),
              ),
              title: t('address.intro.title'),
              body: t('address.intro.description'),
            ),
            track: PresenceMilestoneTrack(
              milestones: _milestones(t),
              numbered: true,
            ),
          ),
          const SizedBox(height: UiSpacing.md),
          AddressIntroDisclosures(background: background),
          const SizedBox(height: UiSpacing.md),
          UiButton(
            label: t('address.intro.start'),
            onPressed: onAcknowledge,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
