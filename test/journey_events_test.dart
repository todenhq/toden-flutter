import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_capture_check.dart';
import 'package:toden_flutter/src/providers/session_progress.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/utils/journey_client.dart';
import 'package:toden_flutter/src/utils/step_log.dart';

// The drop-off journey (user, 2026-11-20): what got in the way, by closed
// code, on the step it happened, so Core can say why an applicant likely
// stopped. No applicant data: codes, steps, times and SDK facts only.
void main() {
  late int saves;
  final t0 = DateTime.utc(2026, 11, 20, 10);

  setUp(() {
    StepLog.reset();
    saves = 0;
    StepLog.onSaveNeeded = () => saves++;
    StepLog.record(VerificationStep.liveness);
  });
  tearDown(() => StepLog.onSaveNeeded = null);

  List<Map<String, dynamic>> events() =>
      ((StepLog.snapshot()?['events'] as List?) ?? const []).cast<Map<String, dynamic>>();

  group('recordEvent', () {
    test('records a code on the step the applicant is on, with its detail', () {
      StepLog.recordEvent('liveness_failed', detail: 'timeout', now: t0);
      expect(events().single, {'code': 'liveness_failed', 'step': 'liveness', 'at': t0.toIso8601String(), 'detail': 'timeout'});
    });

    test('keeps to the closed vocabulary: unknown codes dropped, unknown details become other', () {
      StepLog.recordEvent('typed_their_name', now: t0);
      StepLog.recordEvent('capture_rejected', detail: 'Ada Lovelace', now: t0);
      StepLog.recordEvent('camera_denied', detail: 'anything', now: t0.add(const Duration(seconds: 5)));
      StepLog.recordEvent('error_shown', detail: 'Session Expired!', now: t0.add(const Duration(seconds: 10)));
      StepLog.recordEvent('error_shown', detail: 'session_expired', now: t0.add(const Duration(seconds: 20)));
      expect(events().map((e) => [e['code'], e['detail']]).toList(), [
        ['capture_rejected', 'other'],
        ['camera_denied', null],
        ['error_shown', 'other'],
        ['error_shown', 'session_expired'],
      ]);
    });

    test('collapses the same event inside two seconds, and keeps a later one', () {
      StepLog.recordEvent('upload_failed', detail: 'selfie', now: t0);
      StepLog.recordEvent('upload_failed', detail: 'selfie', now: t0.add(const Duration(milliseconds: 1500)));
      StepLog.recordEvent('upload_failed', detail: 'selfie', now: t0.add(const Duration(seconds: 3)));
      expect(events(), hasLength(2));
    });

    test('drops a trip to the background shorter than a second (a system sheet)', () {
      StepLog.recordEvent('app_backgrounded', now: t0);
      StepLog.recordEvent('app_foregrounded', now: t0.add(const Duration(milliseconds: 600)));
      expect(events(), isEmpty);
      StepLog.recordEvent('app_backgrounded', now: t0.add(const Duration(seconds: 10)));
      StepLog.recordEvent('app_foregrounded', now: t0.add(const Duration(seconds: 40)));
      expect(events().map((e) => e['code']), ['app_backgrounded', 'app_foregrounded']);
    });

    test('keeps the latest 60, dropping the oldest', () {
      for (var i = 0; i < 70; i++) {
        StepLog.recordEvent('code_invalid', detail: i.isEven ? 'email' : 'phone', now: t0.add(Duration(seconds: i * 3)));
      }
      final all = events();
      expect(all, hasLength(60));
      expect(all.first['at'], t0.add(const Duration(seconds: 30)).toIso8601String());
    });

    test('rides the snapshot with the client, and alone keeps the snapshot from being empty', () {
      StepLog.reset();
      StepLog.setClient({'sdk': 'flutter', 'version': '4.2.0', 'platform': 'ios', 'os': 'iOS'});
      expect(StepLog.snapshot(), isNull);
      StepLog.recordEvent('flow_closed', now: t0);
      final snap = StepLog.snapshot()!;
      expect((snap['events'] as List).single['step'], 'unknown');
      expect(snap['client'], {'sdk': 'flutter', 'version': '4.2.0', 'platform': 'ios', 'os': 'iOS'});
    });
  });

  group('saving at once', () {
    test('saves straight after a refused camera, a failed upload, a close or leaving the app', () {
      for (final (i, code) in ['camera_denied', 'upload_failed', 'flow_closed', 'app_backgrounded'].indexed) {
        StepLog.recordEvent(code, detail: code == 'upload_failed' ? 'document' : null, now: t0.add(Duration(seconds: i * 5)));
      }
      expect(saves, 4);
    });

    test('saves from the second failed attempt, not the first', () {
      StepLog.recordEvent('liveness_failed', detail: 'no_face', now: t0);
      expect(saves, 0);
      StepLog.recordEvent('liveness_failed', detail: 'timeout', now: t0.add(const Duration(seconds: 20)));
      expect(saves, 1);
    });

    test('asks at most once in three seconds, and never for a code the applicant fixes in passing', () {
      StepLog.recordEvent('camera_denied', now: t0);
      StepLog.recordEvent('upload_failed', detail: 'selfie', now: t0.add(const Duration(seconds: 1)));
      StepLog.recordEvent('code_resent', detail: 'email', now: t0.add(const Duration(seconds: 10)));
      expect(saves, 1);
    });

    test('a failing save callback never reaches the caller', () {
      StepLog.onSaveNeeded = () => throw StateError('offline');
      expect(() => StepLog.recordEvent('flow_closed', now: t0), returnsNormally);
    });
  });

  group('untouched progress', () {
    Map<String, dynamic> payload(List<String> codes) => {
          'step': 'consent',
          'mediaIds': <String, String>{},
          'stepLog': {
            'events': [for (final c in codes) {'code': c, 'step': 'consent', 'at': t0.toIso8601String()}],
          },
        };

    test('a Close on the opening screen is a journey worth saving', () {
      expect(isUntouchedProgress(payload(['flow_closed'])), isFalse);
    });

    test('coming and going alone is not', () {
      expect(isUntouchedProgress(payload(['app_backgrounded', 'app_foregrounded'])), isTrue);
      expect(isUntouchedProgress(payload([])), isTrue);
    });
  });

  group('closing the flow', () {
    test('is recorded mid-flow, and not once it was submitted', () {
      recordFlowClosed();
      StepLog.record(VerificationStep.submitted);
      recordFlowClosed();
      expect(events().map((e) => e['step']), ['liveness']);
    });
  });

  group('names', () {
    test('OS versions as major.minor at most', () {
      expect(majorMinor('17.2.1'), '17.2');
      expect(majorMinor('15'), '15');
      expect(majorMinor(null), isNull);
      expect(majorMinor('beta'), isNull);
    });

    test('a camera that will not start', () {
      expect(cameraFailureDetail('CameraInUse', null), 'in_use');
      expect(cameraFailureDetail('cameraNotFound', null), 'not_found');
      expect(cameraFailureDetail('setupFailed', 'Something else'), 'other');
    });

    test('uploads by what they carried, and none for the background ones', () {
      expect(uploadDetail('document_front'), 'document');
      expect(uploadDetail('business_document'), 'document');
      expect(uploadDetail('liveness_video'), 'video');
      expect(uploadDetail('selfie'), 'selfie');
      expect(uploadDetail('supporting_document'), 'supporting_document');
      expect(uploadDetail('proof_of_address'), 'proof_of_address');
      expect(uploadDetail('address_photo'), 'other');
      expect(uploadDetail('silent_capture'), isNull);
      expect(uploadDetail('liveness_depth'), isNull);
    });

    test('a failed liveness attempt by why it failed', () {
      expect(livenessFailureDetail('face_lost'), 'no_face');
      expect(livenessFailureDetail('face_swap'), 'face_changed');
      expect(livenessFailureDetail('Challenge timed out'), 'timeout');
      expect(livenessFailureDetail('flash_failed'), 'other');
      expect(livenessFailureDetail('face_lost', multipleFaces: true), 'multiple_faces');
    });

    test('a document photo sent back', () {
      expect(captureRejectionDetail(CaptureProblemKind.notComplete), 'cut_off');
      expect(captureRejectionDetail(CaptureProblemKind.noFace), 'other');
    });

    test('a failed chip read, and none for a read the applicant cancelled', () {
      expect(nfcFailureDetail('cancelled', ''), isNull);
      expect(nfcFailureDetail('unavailable', ''), 'not_supported');
      expect(nfcFailureDetail('auth_failed', ''), 'access_denied');
      expect(nfcFailureDetail('read_failed', 'Polling tag timeout'), 'timeout');
      expect(nfcFailureDetail('tag_lost', 'lost'), 'read_error');
    });

    test('the base client names the SDK, never the device', () {
      final c = baseJourneyClient();
      expect(c['sdk'], 'flutter');
      expect(c.keys, isNot(contains('model')));
    });
  });
}
