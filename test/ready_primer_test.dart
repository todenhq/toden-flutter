import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/gesture_preview_timeline.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/document_specimen.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/widgets/flow_step_meta.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
import 'package:toden_flutter/src/widgets/document_scan_preview.dart';
import 'package:toden_flutter/src/widgets/gesture_preview.dart';
import 'package:toden_flutter/src/widgets/ready_primer.dart';
import 'package:toden_flutter/src/widgets/ready_primer_content.dart';

// ─── The screens before the cameras ───────────────────────────────────────────
//
// The liveness intro shows the camera's window with a cartoon person in it,
// standing on the page, and no stock sentence; the document intro shows the
// chosen document being scanned in its tinted box, with no stock title or
// sentence (the step heading above says them) and the document named in the
// checklist. A workflow's own words always show. The web SDK's
// ReadyPrimer.test.tsx.

VerificationConfig _config([WorkflowTexts? texts]) => VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      texts: texts,
    );

Widget _host(ReadyContent content, {WorkflowTexts? texts}) => ProviderScope(
      overrides: [verificationConfigProvider.overrideWithValue(_config(texts))],
      child: MaterialApp(
        theme: ThemeData(extensions: const [UiColorScheme.light]),
        home: Scaffold(
          body: SizedBox(
            height: 1200,
            child: ReadyPrimer(content: content, onReady: () {}),
          ),
        ),
      ),
    );

ReadyContent _document() => documentReady(
      name: 'Passport',
      subject: const DocumentSpecimenSubject(
        idType: 'passport',
        title: 'Passport',
        country: 'Nigeria',
        side: SpecimenSide.front,
      ),
      aspect: 1.42,
      twoSided: false,
      accent: const Color(0xFF5645F5),
    );

/// The hero's box: the tinted one, or none.
BoxDecoration? _heroBox(WidgetTester tester) {
  final hero = find.ancestor(
    of: find.byWidgetPredicate(
        (w) => w is GesturePreview || w is DocumentScanPreview),
    matching: find.byType(Container),
  );
  return tester.widget<Container>(hero.first).decoration as BoxDecoration?;
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('liveness: the window on the page, the title, and three lines',
      (tester) async {
    await tester.pumpWidget(_host(readyLiveness));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GesturePreview), findsOneWidget);
    expect(_heroBox(tester), isNull, reason: 'no tinted box round the window');
    expect(find.text("Let's confirm you're really here"), findsOneWidget);
    expect(find.text(defaultText('primer.selfie.body')), findsNothing);
    expect(find.text('Put your face in the circle'), findsNothing);
    expect(
        find.text(
            'Take off glasses, hats, caps or anything covering your face'),
        findsOneWidget);
    expect(readyLiveness.checklist.map((i) => i.labelKey), [
      'primer.selfie.checklist2',
      'primer.selfie.checklist4',
      'primer.selfie.checklist5',
    ]);
    await _done(tester);
  });

  testWidgets("liveness: a workflow's own sentence still shows",
      (tester) async {
    await tester.pumpWidget(_host(readyLiveness, texts: {
      'en': {'primer.selfie.body': 'Look at the camera and follow along.'},
    }));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Look at the camera and follow along.'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('passive: holds still, and its own sentence key', (tester) async {
    expect(readyLivenessFor('passive').bodyKey, 'primer.selfie.bodyPassive');
    final hero = readyLivenessFor('passive').hero! as GesturePreview;
    expect(hero.gestures, isEmpty);
    expect((readyLivenessFor('gestures').hero! as GesturePreview).gestures,
        hasLength(4));
  });

  testWidgets('head directions: the picture runs through the four directions',
      (tester) async {
    expect(
      (readyLivenessFor('gestures', gestureSet: 'directions').hero!
              as GesturePreview)
          .gestures,
      kDirectionPreviewGestures,
    );
    // A flash-only check asks for no directions; passive asks for none.
    expect(
      (readyLivenessFor('flash', gestureSet: 'directions').hero!
              as GesturePreview)
          .gestures,
      kAllPreviewGestures,
    );
    expect(readyLivenessFor('passive', gestureSet: 'directions'),
        readyLivenessPassive);
  });

  testWidgets(
      'document: the scan in its tinted box, no stock title or sentence',
      (tester) async {
    await tester.pumpWidget(_host(_document()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DocumentScanPreview), findsOneWidget);
    expect(_heroBox(tester), isNotNull, reason: 'the document sits in the box');
    expect(find.text("You're about to scan your Passport"), findsNothing);
    expect(find.text(defaultText('primer.document.body')), findsNothing);
    expect(find.text('Have your Passport with you'), findsOneWidget);
    expect(find.text('Takes a few seconds'), findsOneWidget);
    await _done(tester);
  });

  testWidgets("document: a workflow's own title and sentence, with the name",
      (tester) async {
    await tester.pumpWidget(_host(_document(), texts: {
      'en': {
        'primer.document.title': 'Get your {document} ready',
        'primer.document.body': 'We read your {document} on this phone.',
      },
    }));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Get your Passport ready'), findsOneWidget);
    expect(find.text('We read your Passport on this phone.'), findsOneWidget);
    await _done(tester);
  });

  test('the texts name the document', () {
    expect(defaultText('primer.document.title', vars: {'document': 'Passport'}),
        "You're about to scan your Passport");
    expect(defaultText('primer.document.body'),
        "We'll read the details for you. Nothing is shared until you submit.");
    expect(
        defaultText('primer.document.checklist1',
            vars: {'document': 'National ID Card'}),
        'Have your National ID Card with you');
    expect(defaultText('primer.document.checklist3'), 'Takes a few seconds');
    expect(
        defaultText('uploadDocument.title.capture',
            vars: {'document': 'Passport'}),
        'Scan Your Passport');
    expect(
        defaultText('uploadDocument.description.capture',
            vars: {'document': 'Passport'}),
        'Place your Passport within the frame.');
    expect(defaultText('presence.title'), 'Face check');
  });

  test('the step heading calls a passport "Passport"', () {
    final passport =
        kCuratedIdTypes['NG']!.firstWhere((id) => id.key == 'passport');
    final meta = flowStepMeta(
      VerificationStep.documentCapture,
      config: _config(),
      state: VerificationState(selectedIdType: passport),
      t: defaultTextFn,
      selfieComplete: false,
    );
    expect(meta.title, 'Scan Your Passport');
    expect(meta.description, 'Place your Passport within the frame.');
  });
}
