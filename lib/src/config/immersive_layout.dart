// ─── The full-screen document camera's layout, as numbers ────────────────────
//
// The overlay (widgets/document_viewfinder.dart) draws from these, and
// documentGuideBand (config/document_guide.dart) reserves the space they take,
// so the guide the overlay draws, the guide the corner gate judges and the
// guide the crop cuts are the same rectangle. Change a control's size here,
// never only in the widget.
//
// Mirrors the React Native SDK's capture/immersiveLayout.ts value for value:
// change both together.
//
// An 8pt rhythm throughout:
//
//   topInset + 8   top bar: back, document pill, side badge (44 high)
//          + 12    the instruction, up to 2 lines
//          + 16    the guide
//          ...
//          + 24    the bottom row: upload, shutter, torch, with captions
//   bottomInset + 16

/// From the top safe inset to the top bar.
const double kImmersiveTopBarOffset = 8;

/// Height of the top bar's controls, and the smallest touch target.
const double kImmersiveTopBarHeight = 44;

/// Left and right margin of the top bar (and the bottom row).
const double kImmersiveSideMargin = 16;

/// Between the top bar's items.
const double kImmersiveTopBarGap = 8;

/// From the top bar to the instruction.
const double kImmersiveHintGap = 12;

/// The instruction's text: 15 on a 20 line, at most 2 lines.
const double kImmersiveHintLineHeight = 20;
const int kImmersiveHintMaxLines = 2;
const double kImmersiveHintPaddingV = 10;

/// The instruction at its tallest.
const double kImmersiveHintMaxHeight =
    kImmersiveHintMaxLines * kImmersiveHintLineHeight +
        2 * kImmersiveHintPaddingV;

/// Clear space between the instruction and the guide.
const double kImmersiveGuideGapBelowHint = 16;

/// Clear space between the top bar and a turned guide (its hint is beside it).
const double kImmersiveGuideGapBelowTopBar = 16;

/// Clear space between the guide and the bottom row.
const double kImmersiveGuideGapAboveControls = 24;

/// From the bottom safe inset to the bottom row.
const double kImmersiveBottomOffset = 16;
const double kImmersiveShutterSize = 80;

/// Upload and torch: round, either side of the shutter.
const double kImmersiveSideButtonSize = 52;
const double kImmersiveCaptionGap = 6;
const double kImmersiveCaptionLineHeight = 16;

/// The bottom row's height: side buttons are centred on the shutter and their
/// captions hang below, so the row runs from the shutter's top to whichever
/// reaches lower, the shutter or a caption.
const double kImmersiveBottomRowHeight = kImmersiveShutterSize / 2 +
    (_kSideButtonReach > kImmersiveShutterSize / 2
        ? _kSideButtonReach
        : kImmersiveShutterSize / 2);

/// How far below the shutter's centre a side button's caption reaches.
const double _kSideButtonReach = kImmersiveSideButtonSize / 2 +
    kImmersiveCaptionGap +
    kImmersiveCaptionLineHeight;

/// The top bar's top edge.
double immersiveTopBarTop(double topInset) => topInset + kImmersiveTopBarOffset;

/// The instruction's top edge, under the top bar.
double immersiveHintTop(double topInset) =>
    immersiveTopBarTop(topInset) + kImmersiveTopBarHeight + kImmersiveHintGap;

/// The lowest the instruction reaches, at 2 lines.
double immersiveHintBottom(double topInset) =>
    immersiveHintTop(topInset) + kImmersiveHintMaxHeight;

/// The bottom row's top edge, measured up from the bottom of the view.
double immersiveBottomRowReserve(double bottomInset) =>
    bottomInset + kImmersiveBottomOffset + kImmersiveBottomRowHeight;
