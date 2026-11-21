import 'package:flutter/widgets.dart';

import '../liveness/gesture_preview_timeline.dart' show kDirectionPreviewGestures;
import 'document_ghost.dart' show DocumentSpecimenSubject;
import 'document_scan_preview.dart';
import 'gesture_preview.dart';
import 'icons/icons.dart';

// ─── "Here's what happens next" copy ─────────────────────────────────────────
//
// A port of the web SDK's ready-primer-content.ts. Kept as data in ONE place
// per platform so the document and liveness screens can't drift from each
// other, and so the two SDKs can be diffed string-for-string.
//
// The words are catalogue texts (a workflow may reword them); this file holds
// their KEYS, and each key's default lives in i18n/defaults_welcome.dart.

@immutable
class ReadyChecklistItem {
  const ReadyChecklistItem(this.icon, this.labelKey);
  final UiIconData icon;

  /// Text key of the line (see i18n/).
  final String labelKey;
}

@immutable
class ReadyContent {
  const ReadyContent({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.checklist,
    this.hero,
    this.ownTitleOnly = false,
    this.ownBodyOnly = false,
    this.heroBoxed = false,
    this.textVars = const {},
  });

  final UiIconData icon;

  /// A picture of the step itself, shown in the hero in place of [icon].
  final Widget? hero;

  /// Text keys of the heading and the paragraph (see i18n/).
  final String titleKey;
  final String bodyKey;

  /// Show the title only where the workflow has written its own, and leave
  /// the SDK's stock one out: for a screen whose step heading above already
  /// says it.
  final bool ownTitleOnly;

  /// The same for the sentence under it: for a screen whose picture, or
  /// heading, already says it.
  final bool ownBodyOnly;

  /// Keep the tinted box round [hero] too, as the glyph has it.
  final bool heroBoxed;

  /// What the texts' `{placeholders}` stand for, such as the document's name.
  final Map<String, String> textVars;

  /// What to expect. Three at most; past that nobody reads it.
  final List<ReadyChecklistItem> checklist;
}

const readyDocument = ReadyContent(
  icon: UiIcons.scanLine,
  titleKey: 'primer.document.title',
  bodyKey: 'primer.document.body',
  checklist: [
    ReadyChecklistItem(UiIcons.idCard, 'primer.document.checklist1'),
    ReadyChecklistItem(UiIcons.sun, 'primer.document.checklist2'),
    ReadyChecklistItem(UiIcons.timer, 'primer.document.checklist3'),
  ],
);

// No "Put your face in the circle" (primer.selfie.checklist1): the picture
// above shows the window, and the camera says it when the face is not in it
// (user, 2026-11-16).
const List<ReadyChecklistItem> _livenessChecklist = [
  ReadyChecklistItem(UiIcons.glasses, 'primer.selfie.checklist2'),
  ReadyChecklistItem(UiIcons.sun, 'primer.selfie.checklist4'),
  ReadyChecklistItem(UiIcons.zapOff, 'primer.selfie.checklist5'),
];

/// The camera's own window, with a cartoon person running through the
/// gestures the camera may ask for. It stands on the page by itself: its own
/// window is its frame. The picture shows what is about to happen, so the
/// stock sentence under the title is left out; a workflow's own is shown.
const readyLiveness = ReadyContent(
  icon: UiIcons.scanFace,
  hero: GesturePreview(),
  titleKey: 'primer.selfie.title',
  bodyKey: 'primer.selfie.body',
  ownBodyOnly: true,
  checklist: _livenessChecklist,
);

/// Passive Liveness asks for no gestures, so its picture shows none (the
/// person holds still, as they will), and a workflow's own description for
/// it is kept apart.
const readyLivenessPassive = ReadyContent(
  icon: UiIcons.scanFace,
  hero: GesturePreview(gestures: []),
  titleKey: 'primer.selfie.title',
  bodyKey: 'primer.selfie.bodyPassive',
  ownBodyOnly: true,
  checklist: _livenessChecklist,
);

/// Head directions: the picture runs through the four directions.
const readyLivenessDirections = ReadyContent(
  icon: UiIcons.scanFace,
  hero: GesturePreview(gestures: kDirectionPreviewGestures),
  titleKey: 'primer.selfie.title',
  bodyKey: 'primer.selfie.body',
  ownBodyOnly: true,
  checklist: _livenessChecklist,
);

/// The primer for the workflow's liveness method and gesture set.
ReadyContent readyLivenessFor(String livenessMode, {String? gestureSet}) =>
    livenessMode == 'passive'
        ? readyLivenessPassive
        : gestureSet == 'directions' && livenessMode != 'flash'
            ? readyLivenessDirections
            : readyLiveness;

/// The document screen for the document the person chose: the camera guide's
/// own sample of it being read (turning over only when it has two sides), and
/// its short name in the words (`{document}`: "Passport", not "International
/// Passport"). The step's heading above already names the document and says
/// what to do, so the stock title and sentence are left out (user,
/// 2026-11-16); a workflow's own words for them are still shown. The picture
/// sits in the screen's tinted box.
ReadyContent documentReady({
  required String name,
  required DocumentSpecimenSubject subject,
  required double aspect,
  required bool twoSided,
  required Color accent,
}) =>
    ReadyContent(
      icon: readyDocument.icon,
      hero: DocumentScanPreview(
        subject: subject,
        aspect: aspect,
        twoSided: twoSided,
        accent: accent,
      ),
      titleKey: readyDocument.titleKey,
      bodyKey: readyDocument.bodyKey,
      checklist: readyDocument.checklist,
      ownTitleOnly: true,
      ownBodyOnly: true,
      heroBoxed: true,
      textVars: {'document': name},
    );
