import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/screen_corners.dart';
import '../config/theme.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';

// ─── Themed bottom sheet ──────────────────────────────────────────────────────
//
// The SDK injects its palette as a ThemeExtension around the flow's CONTENT,
// which lives inside a modal route. A sheet opened from there is a SIBLING
// route, not a descendant — so `Theme.of` there has no UiColorScheme and
// `context.myazaColors` silently falls back to the LIGHT scheme (a white sheet
// over a dark flow). Passing the current ThemeData explicitly into the sheet
// re-establishes the extension no matter where the route lands.
//
// Always open SDK sheets through this helper rather than showModalBottomSheet.
//
// The panel FLOATS: detached from the screen edges by a tight 8px on the
// left, right and bottom (the bottom above the home indicator), with all four
// corners rounded, a faint brand-tinted edge and a slim handle, over a black
// scrim at half strength. A card presented over the flow, not a drawer welded
// to the edge. Mirrors the web SDK's drawer and the RN FloatingSheet; the gap
// is deliberately small so the float reads as intent rather than margin.
// Closing slides it down (the modal route's own exit).

/// The tight gap that detaches the floating card from the screen edges.
/// Public so one-off sheets that cannot route through [showUiSheet]
/// (the Android NFC reading sheet) still share the exact geometry.
const double kUiSheetInset = 8;

/// The least room a sheet keeps between its top and the status bar, as RN's.
const double kUiSheetTopGap = 16;

/// The square-cornered-screen fallback for [myazaSheetRadius]: the web SDK's
/// `--sdk-sheet-radius` default.
const double kUiSheetRadius = 28;

/// The grab handle, so its position can be asserted rather than eyeballed.
const Key kUiSheetHandleKey = Key('myaza-sheet-handle');

/// The float's corner radius is PRESENTATION GRAMMAR, not branding — and it is
/// computed the way Apple computes nested corners: CONCENTRIC with the
/// display, i.e. the device's own corner radius minus the gap, so the sheet's
/// curve runs parallel to the phone's. Square-cornered screens have no curve
/// to be concentric with, so they keep the share-sheet look instead. Never the
/// brand-scaled [UiRadius] tokens: an org whose buttons are 4px square
/// should not get a squared-off bottom sheet. Mirrors the RN FloatingSheet.
double myazaSheetRadius(BuildContext context) {
  final screen = displayCornerRadius(context);
  return screen > 0
      ? math.max(screen - kUiSheetInset, 16.0)
      : kUiSheetRadius;
}

/// The house sheet header: the grab handle at the lip and the round close
/// button, with the sheet's title (and a line under it) when it has one. One
/// header for every sheet, so the close button looks and sits the same
/// wherever a sheet opens. Mirrors the web SDK's `SheetHeader`
/// (components/ui/drawer.tsx) and the RN FloatingSheet.
///
/// Flutter's sheet is drag-dismissible by default, but nothing on screen SAID
/// so: the handle and the close are what tell people. The header is also the
/// drag surface: it is the one part of the panel that never scrolls, so a
/// downward swipe on it reaches the sheet instead of the list.
class _UiSheetHeader extends StatelessWidget {
  const _UiSheetHeader({this.title, this.description});

  final String? title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final handle = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        // Keyed so a test can measure where it sits. The layout that put it
        // halfway down the panel read as correct in review.
        key: kUiSheetHandleKey,
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: myazaHandleColor(colors, light: colors.border),
          borderRadius: BorderRadius.circular(UiRadius.full),
        ),
      ),
    );
    final title = this.title;

    if (title == null) {
      // Concentric corners put the panel's edge further in, so the button
      // follows the curve rather than sitting on it.
      final inset = (myazaSheetRadius(context) * 0.42).clamp(16.0, 26.0);
      // A STACK, not a row: in a row the handle centres against the close
      // button's 44pt touch box and rides halfway down the panel.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: inset - 6),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            handle,
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(top: (inset - 12).clamp(2.0, 12.0)),
                child: const UiSheetCloseButton(),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: handle),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: text.heading3.copyWith(height: 1.5)),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description!,
                          style: text.bodySmall.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const UiSheetCloseButton(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The sheet's close: a 32px round muted button with the X, inside a 44pt
/// touch target. The select sheet's, on every sheet.
class UiSheetCloseButton extends StatelessWidget {
  const UiSheetCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      tooltip: 'Close',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.backgroundSecondary, shape: BoxShape.circle),
        child: UiIcon(UiIcons.x, size: 16, color: colors.textSecondary),
      ),
    );
  }
}

Future<T?> showUiSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,

  /// Off for a sheet that draws its own dismiss affordance, so the two do not
  /// stack into a panel with two close buttons.
  bool showHeader = true,

  /// The sheet's heading in the house header (what is being picked or
  /// edited), and an optional line under it.
  String? title,
  String? description,
}) {
  final theme = Theme.of(context);
  final colors = context.myazaColors;

  // A tall sheet must stop BELOW the status bar (a full-height panel on a
  // notched phone ran its header under the Dynamic Island). The same 8 that
  // detaches the card at the sides and bottom detaches it at the top. The
  // flow's scope rides along so the sheet reads the flow's texts.
  //
  // The top inset is the DEVICE's, read off the view: inside the flow the
  // status bar is often already consumed (a SafeArea or a padding-free route
  // above this context), so MediaQuery here said 0 and a long form grew under
  // the Dynamic Island. Never closer than 16 below it; the body scrolls.
  final media = MediaQuery.of(context);
  final statusBar = MediaQueryData.fromView(View.of(context)).padding.top;
  final maxHeight = media.size.height - statusBar - kUiSheetTopGap;
  final scope = flowScopeOf(context);

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    // The web SDK's overlay: black at half strength.
    barrierColor: Colors.black.withValues(alpha: 0.5),
    constraints: BoxConstraints(maxHeight: math.max(maxHeight, 120)),
    builder: (sheetContext) {
      // The CARD floats: a tight 8px off the screen's sides AND bottom, with
      // the home indicator riding on the card, as the RN sheet sits (system
      // share sheet style). Reserving the safe area under it as well left the
      // card hovering high with a wide foot. No inner foot either: a scrolling
      // body runs all the way to the lip and is CLIPPED by the curve.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          kUiSheetInset,
          0,
          kUiSheetInset,
          kUiSheetInset,
        ),
        child: Material(
          color: colors.background,
          clipBehavior: Clip.antiAlias,
          // A hairline edge in the brand's tint, so the panel separates from
          // the flow behind it on either theme. `shape` rather than
          // `borderRadius`: Material takes one or the other, and only shape
          // carries a side.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(myazaSheetRadius(sheetContext)),
            // A faint brand-tinted edge, as the web and RN sheets draw it.
            side: BorderSide(color: colors.primary.withValues(alpha: 0.2)),
          ),
          // The card floats clear of the home indicator, so a body's own
          // SafeArea must not pad for it a second time.
          child: MediaQuery.removePadding(
            context: sheetContext,
            removeBottom: true,
            child: inFlowScope(scope, Theme(
              data: theme,
              child: showHeader
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _UiSheetHeader(title: title, description: description),
                        Flexible(child: Builder(builder: builder)),
                      ],
                    )
                  : Builder(builder: builder),
            )),
          ),
        ),
      );
    },
  );
}

/// A date, picked from a calendar in the house sheet (what is being picked as
/// its header title), as the web SDK's DateField opens on a phone. The
/// calendar carries the SDK palette: `CalendarDatePicker` builds off
/// `ColorScheme`, not our extension, so without this it took the host app's
/// colours (a light calendar over a dark flow). Picking a day closes it.
Future<DateTime?> showUiDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
}) {
  final colors = context.myazaColors;
  // The flow's theme is derived from the consumer's appearance overrides, so
  // `theme.brightness` tracks the HOST app, not the flow. Read the flow's own
  // background instead.
  final isDark = colors.background.computeLuminance() < 0.5;
  final base = isDark ? const ColorScheme.dark() : const ColorScheme.light();
  final initial = initialDate.isBefore(firstDate)
      ? firstDate
      : initialDate.isAfter(lastDate)
          ? lastDate
          : initialDate;

  return showUiSheet<DateTime>(
    context,
    isScrollControlled: true,
    title: title ?? 'Pick a date',
    builder: (sheetContext) => Theme(
      data: Theme.of(sheetContext).copyWith(
        colorScheme: base.copyWith(
          primary: colors.primary,
          onPrimary: colors.onPrimary,
          surface: colors.background,
          onSurface: colors.textDark,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: CalendarDatePicker(
            initialDate: initial,
            firstDate: firstDate,
            lastDate: lastDate,
            onDateChanged: (date) => Navigator.of(sheetContext).pop(date),
          ),
        ),
      ),
    ),
  );
}
