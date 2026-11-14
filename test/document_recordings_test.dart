import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/document_recordings.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:toden_flutter/src/services/api_service.dart';

// ─── A side submits only its own recording ───────────────────────────────────
//
// The server compares each still with the recording of the same side to catch
// an injected capture. The notifier could only ever SET a recording id, so a
// retake with no recording of its own (a gallery photo, a clip that would not
// compress or upload) was submitted beside the earlier capture's recording, and
// a back from a two-sided ID picked earlier rode along with a passport.

class _Api extends VerificationApiService {
  _Api() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  VerifyRequest? submitted;

  @override
  Future<VerifyResponse> verify(VerifyRequest request) async {
    submitted = request;
    return const VerifyResponse(verificationId: 'ver_1', status: 'pending');
  }

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(
      String sessionId, Map<String, dynamic> progress) async {}
}

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

IdTypeConfig _ng(String key) =>
    kCuratedIdTypes['NG']!.firstWhere((t) => t.key == key);

(ProviderContainer, _Api) _container() {
  final api = _Api();
  final c = ProviderContainer(overrides: [
    verificationConfigProvider.overrideWithValue(const VerificationConfig(
      apiKey: 'pk_test_stub',
      country: 'NG',
      silentCapture: false,
      userId: 'user_1',
    )),
    verificationApiServiceProvider.overrideWithValue(api),
    preloadedServerConfigProvider.overrideWithValue(
      const ServerSdkConfig(status: ServerConfigStatus.ready),
    ),
  ]);
  return (c, api);
}

var _next = 0;

/// Continue, as the capture screen runs it, with a fake upload.
Future<void> _continue(
  VerificationNotifier notifier, {
  required String? front,
  String? back,
  bool backCaptured = false,
  bool recordingsUpload = true,
}) =>
    uploadDocumentSides(
      sides: [
        DocumentSideUpload(side: 'front', still: _jpeg, recording: front),
        if (backCaptured)
          DocumentSideUpload(side: 'back', still: _jpeg, recording: back),
      ],
      clearDocumentMedia: notifier.clearDocumentMedia,
      uploadStill: (side) async => 'med_${side.side}_${++_next}',
      uploadRecording: (side, path) async =>
          recordingsUpload ? 'med_video_$path' : null,
      onStill: (side, id) => notifier.setDocumentMediaId(id, side: side),
      onRecording: (side, id) => notifier.setMediaId(
        side == 'back' ? 'documentBackVideo' : 'documentFrontVideo',
        id,
      ),
      active: () => true,
    );

Future<Map<String, dynamic>> _wire(
    VerificationNotifier notifier, _Api api) async {
  await notifier.submitAsync();
  return (api.submitted!.toJson()['mediaIds'] as Map).cast<String, dynamic>();
}

void main() {
  test('a retake with no recording submits no recording for that side',
      () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setIdType(_ng('passport'));

    await _continue(notifier, front: 'take1.mp4');
    expect(c.read(kYCNotifierProvider).mediaIds.documentFrontVideo,
        'med_video_take1.mp4');

    // Retaken, then a photo from the gallery: no recording.
    await _continue(notifier, front: null);

    final ids = await _wire(notifier, api);
    expect(ids['documentFront'], isNotNull);
    expect(ids.containsKey('documentFrontVideo'), isFalse);
  });

  test('a retake whose recording fails to upload submits no recording',
      () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setIdType(_ng('pvc'));

    await _continue(notifier,
        front: 'f1.mp4', back: 'b1.mp4', backCaptured: true);
    await _continue(notifier,
        front: 'f2.mp4',
        back: 'b2.mp4',
        backCaptured: true,
        recordingsUpload: false);

    final ids = await _wire(notifier, api);
    expect(ids.containsKey('documentFrontVideo'), isFalse);
    expect(ids.containsKey('documentBackVideo'), isFalse);
  });

  test('a retake with a recording submits the new one', () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setIdType(_ng('passport'));

    await _continue(notifier, front: 'take1.mp4');
    await _continue(notifier, front: 'take2.mp4');

    final ids = await _wire(notifier, api);
    expect(ids['documentFrontVideo'], 'med_video_take2.mp4');
  });

  test('a one-sided ID does not carry the back of a two-sided ID', () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setIdType(_ng('pvc'));
    await _continue(notifier,
        front: 'card-front.mp4', back: 'card-back.mp4', backCaptured: true);

    notifier.setIdType(_ng('passport'));
    await _continue(notifier, front: 'passport.mp4');

    final ids = await _wire(notifier, api);
    expect(ids['documentFrontVideo'], 'med_video_passport.mp4');
    expect(ids.containsKey('documentBack'), isFalse);
    expect(ids.containsKey('documentBackVideo'), isFalse);
  });

  test('clearing the document keeps the selfie and its recording', () {
    final (c, _) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setMediaId('selfie', 'med_selfie');
    notifier.setMediaId('livenessVideo', 'med_liveness');
    notifier.setMediaId('documentFrontVideo', 'med_old');
    notifier.clearDocumentMedia();
    final media = c.read(kYCNotifierProvider).mediaIds;
    expect(media.selfie, 'med_selfie');
    expect(media.livenessVideo, 'med_liveness');
    expect(media.documentFrontVideo, isNull);
  });

  test('the capture screen uploads through uploadDocumentSides', () {
    final src = File('lib/src/screens/document_capture_screen.dart')
        .readAsStringSync();
    expect(src, contains('await uploadDocumentSides('));
    expect(src, contains('clearDocumentMedia: notifier.clearDocumentMedia,'));
    // A shot with no clip stores none, never an earlier try's.
    expect(src, isNot(contains('if (path == null) return;')));
  });
}
