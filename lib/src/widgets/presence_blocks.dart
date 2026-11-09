import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import 'presence_milestone_track.dart';
import 'presence_milestones.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';
import '../presence/background_ask_controller.dart';
import 'ui_button.dart';

/// The success screen's presence card, drawn as a LIVE PROCESS rather than a
/// notice: the check began the moment they submitted, so the badge pulses and
/// the first milestone is already filled.
///
/// Its copy is a lockstep mirror of the web and RN SDKs' PresenceExpectations,
/// and of the intro gate's milestones — the promise made at the start of the
/// address flow and the card at the end are two frames of one story.
class PresenceExpectations extends StatelessWidget {
  const PresenceExpectations({super.key, this.background, this.finishLine, this.onTurnOn});

  /// The "allow all the time" answer: [BackgroundOutcome.off] swaps the header
  /// for the work still to do ([finishLine]) and a way to turn checks on;
  /// null keeps the usual wording.
  final BackgroundOutcome? background;
  final String? finishLine;
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    // Catalogue texts (a workflow may reword them); defaults in i18n/.
    final t = context.verificationText;
    final off = background == BackgroundOutcome.off;
    final body = off && finishLine != null
        ? finishLine!
        : background == BackgroundOutcome.on
            ? 'Automatic checks are on. Nothing else for you to do.'
            : t('address.presence.description');
    PresenceMilestone milestone(int n, UiIconData icon) => PresenceMilestone(
          icon: icon,
          stage: t('address.presence.step$n.stage'),
          title: t('address.presence.step$n.title'),
          caption: t('address.presence.step$n.caption'),
          active: n == 1,
        );
    final card = Padding(
      padding: const EdgeInsets.only(top: UiSpacing.lg),
      child: PresenceCard(
        header: PresenceHeaderBand(
          badge: PresenceBadge(
            leading: const _LiveDot(),
            label: t('address.presence.badge'),
          ),
          title: off ? t('address.presence.off.title') : t('address.presence.title'),
          body: body,
          compact: true,
        ),
        track: PresenceMilestoneTrack(
          milestones: [
            milestone(1, UiIcons.mapPinCheck),
            milestone(2, UiIcons.radar),
            milestone(3, UiIcons.bellRing),
          ],
          medallion: 32,
        ),
      ),
    );
    if (!off || onTurnOn == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: UiSpacing.sm + 4),
        UiButton(
          label: t('address.background.allow'),
          variant: UiButtonVariant.outline,
          onPressed: onTurnOn,
        ),
      ],
    );
  }
}

/// The pulsing dot that says the check is running right now, not scheduled.
class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return SizedBox(
      width: 8,
      height: 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(begin: 1, end: 2.2, duration: 1200.ms)
              .fadeOut(duration: 1200.ms),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: colors.primary, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
