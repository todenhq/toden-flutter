import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/immersive_layout.dart';
import 'package:toden_flutter/src/config/id_types.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/widgets/country_flag.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
import 'package:toden_flutter/src/widgets/document_info_pill.dart';
import 'package:toden_flutter/src/widgets/document_viewfinder.dart';
import 'package:toden_flutter/src/widgets/icons/icons.dart';
import 'icon_finder.dart';

// The full-screen viewfinder stacks controls over a live camera, where a
// mis-parented or overlapping child is invisible in tests but obvious (and
// unusable) on a phone — the hint spent a build sitting behind the shutter.
// These render it for real and assert the things that actually broke.

// context.myazaColors falls back to the light scheme without a UiTheme
// ancestor, so a plain MaterialApp is enough here.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

DocumentViewfinder _viewfinder({
  DocumentHint hint = DocumentHint.searching,
  IdTypeConfig? idType,
  VoidCallback? onUpload,
  VoidCallback? onToggleTorch,
  bool torchOn = false,
  bool isBack = false,
  String hintLabel = 'Passport',
  DocumentFraming framing = DocumentFraming.none,
}) =>
    DocumentViewfinder(
      controller: null,
      isLoading: false,
      error: null,
      isBack: isBack,
      isProcessing: false,
      guideAspect: 1.586,
      framing: framing,
      onCapture: () {},
      hint: hint,
      hintLabel: hintLabel,
      idType: idType,
      country: 'NG',
      onBack: () {},
      onUpload: onUpload,
      onToggleTorch: onToggleTorch,
      torchOn: torchOn,
    );

/// Sizes the test view as a phone, with its system-bar insets.
void _phone(WidgetTester tester,
    {double width = 393,
    double height = 852,
    double top = 59,
    double bottom = 34}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders without a ParentDataWidget error', (tester) async {
    // A Positioned nested in the bottom Column compiles fine and throws only at
    // runtime — which is exactly how the info pill first shipped.
    await tester.pumpWidget(_host(_viewfinder()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hint never sits behind the shutter', (tester) async {
    await tester.pumpWidget(_host(_viewfinder(
      hint: DocumentHint.wrongDocument,
      onUpload: () {},
    )));
    await tester.pump();

    final hint = tester.getRect(find.byKey(kDocumentHintKey));
    final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
    expect(hint.bottom, lessThanOrEqualTo(shutter.top),
        reason: 'hint overlaps the shutter');
  });

  testWidgets('the torch sits on the shutter row, not the top corner',
      (tester) async {
    await tester.pumpWidget(_host(_viewfinder(onToggleTorch: () {})));
    await tester.pump();

    final torch = tester.getRect(find.byKey(kDocumentTorchKey));
    final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
    // Same row as the shutter, and to its right.
    expect(torch.center.dy, closeTo(shutter.center.dy, 8));
    expect(torch.left, greaterThan(shutter.right));
  });

  testWidgets('the shutter stays centred with or without a torch',
      (tester) async {
    for (final onToggleTorch in [null, () {}]) {
      await tester.pumpWidget(_host(_viewfinder(onToggleTorch: onToggleTorch)));
      await tester.pump();
      final screen = tester.getRect(find.byType(DocumentViewfinder));
      final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
      expect(shutter.center.dx, closeTo(screen.center.dx, 1),
          reason: 'shutter drifts off centre when torch is '
              '${onToggleTorch == null ? "absent" : "present"}');
    }
  });

  testWidgets('shows the ID type and country when given one', (tester) async {
    final idType = curatedIdType('NG', 'passport')!;
    await tester.pumpWidget(_host(_viewfinder(idType: idType)));
    await tester.pump();

    expect(find.byType(DocumentInfoPill), findsOneWidget);
    // The flag stands in for the country; the name would be the same fact twice.
    expect(find.byType(UiCountryFlag), findsOneWidget);
    expect(find.text('Nigeria'), findsNothing);
    // Shown short: the catalogue label ("International Passport") is written
    // for a picker, not for a pill beside a flag.
    expect(find.text('Passport'), findsOneWidget);
  });

  // AnimatedOpacity builds a FadeTransition, not an Opacity.
  double ghostOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(DocumentGhost),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  testWidgets('the sample shows, then fades slowly out of the way',
      (tester) async {
    await tester.pumpWidget(_host(_viewfinder()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(ghostOpacity(tester), kDocumentGhostOpacity,
        reason: 'see-through, so the camera stays visible behind it');

    // It is guidance for an empty frame: it must not sit over the document for
    // the whole session, and it must not blink off either.
    await tester.pump(kDocumentGhostDuration);
    await tester.pump(kDocumentGhostFade ~/ 2);
    expect(ghostOpacity(tester), greaterThan(0));
    await tester.pump(kDocumentGhostFade);
    expect(ghostOpacity(tester), 0);
  });

  testWidgets(
      'a framed document ends the sample, but only once it has been read',
      (tester) async {
    await tester
        .pumpWidget(_host(_viewfinder(framing: DocumentFraming.holding)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(ghostOpacity(tester), kDocumentGhostOpacity);

    await tester.pump(kDocumentGhostMinimum);
    await tester.pump(kDocumentGhostFade + const Duration(milliseconds: 100));
    expect(ghostOpacity(tester), 0);
  });

  testWidgets(
      'top controls clear the status bar through a removePadding '
      'ancestor', (tester) async {
    // Reproduces the real tree: the flow is shown with
    // showModalBottomSheet(useSafeArea: false), which Flutter wraps in
    // MediaQuery.removePadding(removeTop: true) — that zeroes padding.top AND
    // reduces viewPadding.top to zero, so reading either from the inherited
    // MediaQuery puts the back button under the status bar.
    const statusBar = 59.0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(top: statusBar * 3);
    tester.view.padding = const FakeViewPadding(top: statusBar * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => MediaQuery.removePadding(
          context: ctx,
          removeTop: true,
          child: Scaffold(body: _viewfinder(onToggleTorch: () {})),
        ),
      ),
    ));
    await tester.pump();

    final back = tester.getRect(findUiIcon(UiIcons.arrowLeft));
    expect(back.top, greaterThanOrEqualTo(statusBar),
        reason: 'back button overlaps the status bar');
  });

  testWidgets('without an ID type the pill names the step\'s own label',
      (tester) async {
    await tester.pumpWidget(_host(_viewfinder(hintLabel: 'Driver\'s licence')));
    expect(find.byType(DocumentInfoPill), findsOneWidget);
    expect(find.text('Driver\'s licence'), findsOneWidget);
  });

  group('the immersive layout', () {
    testWidgets('back, document and side sit on one 44 row at the top bar',
        (tester) async {
      _phone(tester);
      final idType = curatedIdType('NG', 'passport')!;
      await tester.pumpWidget(_host(_viewfinder(idType: idType)));
      await tester.pump();

      final back = tester.getRect(find.byKey(kDocumentBackKey));
      final pill = tester.getRect(find.byType(DocumentInfoPill));
      final badge = tester.getRect(find.byKey(kDocumentSideBadgeKey));
      for (final r in [back, pill, badge]) {
        expect(r.top, immersiveTopBarTop(59));
        expect(r.height, kImmersiveTopBarHeight);
      }
      expect(back.width, kImmersiveTopBarHeight, reason: 'round back button');
      expect(back.left, kImmersiveSideMargin);
      expect(badge.right, 393 - kImmersiveSideMargin);
      expect(pill.center.dx, closeTo(393 / 2, 0.5), reason: 'pill centred');
      expect(pill.left, greaterThanOrEqualTo(back.right + kImmersiveTopBarGap));
      expect(pill.right, lessThanOrEqualTo(badge.left - kImmersiveTopBarGap));
      expect(find.text('FRONT'), findsOneWidget);
    });

    testWidgets('a long document name truncates rather than meeting the sides',
        (tester) async {
      _phone(tester, width: 320, height: 640, top: 24, bottom: 0);
      await tester.pumpWidget(_host(_viewfinder(
          isBack: true,
          hintLabel: 'Economic Community of West African States ID Card')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final pill = tester.getRect(find.byType(DocumentInfoPill));
      final back = tester.getRect(find.byKey(kDocumentBackKey));
      final badge = tester.getRect(find.byKey(kDocumentSideBadgeKey));
      expect(pill.left, greaterThanOrEqualTo(back.right + kImmersiveTopBarGap));
      expect(pill.right, lessThanOrEqualTo(badge.left - kImmersiveTopBarGap));
      expect(pill.center.dx, closeTo(160, 0.5));
      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('the instruction sits 12 under the top bar, at most 88% wide',
        (tester) async {
      _phone(tester);
      await tester
          .pumpWidget(_host(_viewfinder(hint: DocumentHint.spaceAround)));
      await tester.pump();

      final hint = tester.getRect(find.byKey(kDocumentHintKey));
      expect(hint.top, immersiveHintTop(59));
      // Two lines and the padding, plus the 1-wide hairline either side (drawn
      // outside the padding, as React Native's borderWidth is).
      expect(hint.height, lessThanOrEqualTo(kImmersiveHintMaxHeight + 2));
      expect(hint.width, lessThanOrEqualTo(393 * 0.88 + 0.01));
      expect(hint.center.dx, closeTo(393 / 2, 0.5));
    });

    testWidgets(
        'upload, shutter and torch share the bottom row, 16 above the '
        'safe inset', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
          _host(_viewfinder(onUpload: () {}, onToggleTorch: () {})));
      await tester.pump();

      final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
      final upload = tester.getRect(find.byKey(kDocumentUploadKey));
      final torch = tester.getRect(find.byKey(kDocumentTorchKey));
      expect(shutter.size, const Size.square(kImmersiveShutterSize));
      expect(shutter.top, 852 - immersiveBottomRowReserve(34),
          reason: 'the row starts at the shutter\'s top');
      expect(upload.center.dy, closeTo(shutter.center.dy, 0.01));
      expect(torch.center.dy, closeTo(shutter.center.dy, 0.01));
      expect(upload.right, lessThan(shutter.left));
      // Three equal slots: the side buttons mirror each other about the shutter.
      expect(shutter.center.dx - upload.center.dx,
          closeTo(torch.center.dx - shutter.center.dx, 0.01));
      // A target of at least 56 around the 52 button.
      expect(upload.width, greaterThanOrEqualTo(56));
      expect(upload.height, greaterThanOrEqualTo(56));

      // Captions hang 6 under the 52 buttons, inside the row.
      final caption = tester.getRect(find.text(kUploadCaption));
      expect(caption.top,
          closeTo(upload.center.dy + kImmersiveSideButtonSize / 2 + 6, 0.01));
      expect(caption.bottom, lessThanOrEqualTo(852 - 34 - 16 + 0.01));
      expect(find.text(kTorchCaptionOff), findsOneWidget);
    });

    testWidgets('the torch caption says when the light is on', (tester) async {
      await tester
          .pumpWidget(_host(_viewfinder(onToggleTorch: () {}, torchOn: true)));
      expect(find.text(kTorchCaptionOn), findsOneWidget);
      expect(find.text(kTorchCaptionOff), findsNothing);
    });

    testWidgets(
        'upload is the bottom row\'s left button, labelled for screen '
        'readers', (tester) async {
      var picked = 0;
      await tester.pumpWidget(_host(_viewfinder(onUpload: () => picked++)));
      await tester.pump();

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Upload a photo instead')),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          label: 'Upload a photo instead',
          hint: 'Choose a photo of your document instead of using the camera.',
        ),
      );
      handle.dispose();

      await tester.tap(find.byKey(kDocumentUploadKey));
      expect(picked, 1);
      // The old pill above the shutter is gone.
      expect(find.text('Upload a photo instead'), findsNothing);
    });

    testWidgets('no upload and no torch leave their slots empty',
        (tester) async {
      await tester.pumpWidget(_host(_viewfinder()));
      expect(find.byKey(kDocumentUploadKey), findsNothing);
      expect(find.byKey(kDocumentTorchKey), findsNothing);
      expect(find.text(kUploadCaption), findsNothing);
    });
  });
}
