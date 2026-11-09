import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/document_capture_methods.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/screens/consent_process_steps.dart';
import 'package:toden_flutter/src/widgets/document_upload_only_view.dart';

// ─── Scan, upload, or both ────────────────────────────────────────────────────
//
// `allowDocumentScan` mirrors `allowDocumentUpload`. At least one stays on: a
// config carrying both off (a stored snapshot, a prop mount) falls back to the
// camera rather than leaving the document step with no way through.

void main() {
  group('documentCaptureMethods', () {
    test('both on by default', () {
      final m = documentCaptureMethods(
          allowDocumentScan: true, allowDocumentUpload: true);
      expect(m, const DocumentCaptureMethods(scan: true, upload: true));
      expect(m.uploadOnly, isFalse);
    });

    test('scan off leaves upload only', () {
      final m = documentCaptureMethods(
          allowDocumentScan: false, allowDocumentUpload: true);
      expect(m, const DocumentCaptureMethods(scan: false, upload: true));
      expect(m.uploadOnly, isTrue);
    });

    test('upload off leaves scan only', () {
      final m = documentCaptureMethods(
          allowDocumentScan: true, allowDocumentUpload: false);
      expect(m, const DocumentCaptureMethods(scan: true, upload: false));
      expect(m.uploadOnly, isFalse);
    });

    test('both off falls back to the camera', () {
      final m = documentCaptureMethods(
          allowDocumentScan: false, allowDocumentUpload: false);
      expect(m, const DocumentCaptureMethods(scan: true, upload: false));
      expect(m.uploadOnly, isFalse);
    });

    test('reads a config, defaulting both on', () {
      const config = VerificationConfig(apiKey: 'pk_test_x', country: 'NG');
      expect(config.allowDocumentScan, isTrue);
      expect(documentCaptureMethodsFor(config),
          const DocumentCaptureMethods(scan: true, upload: true));
      expect(
        documentCaptureMethodsFor(config.copyWith(allowDocumentScan: false))
            .uploadOnly,
        isTrue,
      );
    });
  });

  group('workflow plumbing', () {
    const base = VerificationConfig(apiKey: 'pk_test_x', country: 'NG');

    test('the flow payload parses the key, absent is null', () {
      expect(
        WorkflowFlowConfig.fromJson({'allowDocumentScan': false})
            .allowDocumentScan,
        isFalse,
      );
      expect(WorkflowFlowConfig.fromJson(const {}).allowDocumentScan, isNull);
    });

    test("a flow's value wins, and an absent key keeps the host's", () {
      final merged = mergeWorkflowIntoConfig(
        base,
        WorkflowFlowConfig.fromJson({'allowDocumentScan': false}),
      );
      expect(merged.allowDocumentScan, isFalse);
      expect(documentCaptureMethodsFor(merged).uploadOnly, isTrue);

      final kept = mergeWorkflowIntoConfig(
        base.copyWith(allowDocumentScan: false),
        WorkflowFlowConfig.fromJson(const {}),
      );
      expect(kept.allowDocumentScan, isFalse);
    });

    test('a flow with both off still scans', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        WorkflowFlowConfig.fromJson(
            {'allowDocumentScan': false, 'allowDocumentUpload': false}),
      );
      expect(documentCaptureMethodsFor(merged),
          const DocumentCaptureMethods(scan: true, upload: false));
    });

    test('the applicant overlay carries the mapped workflow value', () {
      final merged = overlayApplicantWorkflow(
        base,
        const ApplicantWorkflow(
          id: 'wf_applicant',
          name: 'Identity verification',
          version: 1,
          config: {'allowDocumentScan': false},
        ),
      );
      expect(merged.allowDocumentScan, isFalse);
    });

    test('the workflow sets the review and audio, and absent keeps the host\'s', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        WorkflowFlowConfig.fromJson({'documentReview': true, 'documentAudio': true}),
      );
      expect(merged.documentReview, isTrue);
      expect(merged.documentAudio, isTrue);

      final kept = mergeWorkflowIntoConfig(base, WorkflowFlowConfig.fromJson(const {}));
      expect(kept.documentReview, isFalse);
      expect(kept.documentAudio, isFalse);
    });

    test('the applicant overlay carries the review and audio too', () {
      final merged = overlayApplicantWorkflow(
        base,
        const ApplicantWorkflow(
          id: 'wf_applicant',
          name: 'Identity verification',
          version: 1,
          config: {'documentReview': true, 'documentAudio': true},
        ),
      );
      expect(merged.documentReview, isTrue);
      expect(merged.documentAudio, isTrue);
    });
  });

  group('afterDocumentCapture', () {
    const camera = DocumentSideSource.camera;
    const upload = DocumentSideSource.upload;

    AfterDocumentCapture next({
      bool review = false,
      bool isBack = false,
      bool twoSided = false,
      DocumentSideSource? front = camera,
      DocumentSideSource? back,
      bool hasBack = false,
    }) =>
        afterDocumentCapture(
          documentReview: review,
          isBack: isBack,
          twoSided: twoSided,
          front: front,
          back: back,
          hasBack: hasBack,
        );

    test('review on keeps every screen', () {
      expect(next(review: true), AfterDocumentCapture.review);
      expect(next(review: true, twoSided: true), AfterDocumentCapture.previewFront);
      expect(next(review: true, twoSided: true, isBack: true, back: camera, hasBack: true),
          AfterDocumentCapture.review);
    });

    test('a one-sided scan hands over', () {
      expect(next(), AfterDocumentCapture.handOver);
    });

    test('a scanned front moves on to the back, then hands over', () {
      expect(next(twoSided: true), AfterDocumentCapture.scanBack);
      expect(next(twoSided: true, isBack: true, back: camera, hasBack: true),
          AfterDocumentCapture.handOver);
    });

    test('a retaken front with the back still scanned hands over', () {
      expect(next(twoSided: true, back: camera, hasBack: true),
          AfterDocumentCapture.handOver);
    });

    test('an uploaded photo always keeps the screen', () {
      expect(next(front: upload), AfterDocumentCapture.review);
      expect(next(twoSided: true, front: upload), AfterDocumentCapture.previewFront);
      expect(next(twoSided: true, isBack: true, back: upload, hasBack: true),
          AfterDocumentCapture.review);
      expect(next(twoSided: true, back: upload, hasBack: true),
          AfterDocumentCapture.previewFront);
    });

    test('a restored back keeps the screen', () {
      expect(next(twoSided: true, hasBack: true), AfterDocumentCapture.previewFront);
    });
  });

  group('recordsDocumentAudio', () {
    VerificationConfig config({bool audio = true, bool scan = true}) =>
        VerificationConfig(
          apiKey: 'pk_test_x',
          country: 'NG',
          documentAudio: audio,
          allowDocumentScan: scan,
        );

    test('only when asked for, and only with a camera to record', () {
      expect(recordsDocumentAudio(config()), isTrue);
      expect(recordsDocumentAudio(config(audio: false)), isFalse);
      expect(recordsDocumentAudio(config(scan: false)), isFalse);
    });

    test('is not on the consent list', () {
      final labels = consentProcessSteps(
        config(),
        isBusiness: false,
        scope: null,
        t: defaultTextFn,
      ).map((s) => s.label).join(' ');
      expect(labels.toLowerCase(), isNot(contains('sound')));
    });
  });

  group('DocumentUploadOnlyView', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData(extensions: const [UiColorScheme.light]),
          home: Scaffold(body: child),
        ));

    testWidgets('asks for the front and opens the picker', (tester) async {
      var picks = 0;
      await pump(
        tester,
        DocumentUploadOnlyView(
          idTypeLabel: 'Passport',
          isBack: false,
          aspect: 1.42,
          isBusy: false,
          onPick: () => picks++,
        ),
      );
      expect(find.text('Front of your Passport'), findsOneWidget);
      // The card is the only control: the button that used to sit under it
      // is gone, and the card carries the call to action itself.
      expect(find.text('Choose a photo of the front'), findsNothing);
      expect(find.text('Tap to choose a photo'), findsOneWidget);
      await tester.tap(find.byKey(kDocumentUploadTargetKey));
      expect(picks, 1);
    });

    testWidgets('the back side, busy, cannot pick and shows the error',
        (tester) async {
      var picks = 0;
      await pump(
        tester,
        DocumentUploadOnlyView(
          idTypeLabel: "Driver's Licence",
          isBack: true,
          aspect: 1.586,
          isBusy: true,
          error: 'We could not read that photo. Please try another.',
          onPick: () => picks++,
        ),
      );
      expect(find.text("Back of your Driver's Licence"), findsOneWidget);
      expect(find.text('Preparing your photo…'), findsOneWidget);
      expect(find.text("Couldn't use that photo"), findsOneWidget);
      await tester.tap(find.byKey(kDocumentUploadTargetKey),
          warnIfMissed: false);
      expect(picks, 0);
    });
  });
}
