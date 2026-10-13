import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/selfie_upload_wait.dart';

// A tiny store: a snapshot the test mutates, and listeners it notifies.
class _FakeStore {
  SelfieUploadSnapshot snapshot;
  final listeners = <void Function()>{};
  _FakeStore(this.snapshot);

  SelfieUploadSnapshot read() => snapshot;
  void Function() subscribe(void Function() l) {
    listeners.add(l);
    return () => listeners.remove(l);
  }

  void set(SelfieUploadSnapshot next) {
    snapshot = next;
    for (final l in listeners.toList()) {
      l();
    }
  }
}

void main() {
  group('selfieUploadExpected', () {
    const idle = SelfieUploadSnapshot(selfieUpload: kIdleSelfieUpload);
    test('a flow with no liveness step and nothing uploading has no selfie to wait for', () {
      expect(selfieUploadExpected(idle, hasLivenessStep: false), isFalse);
    });
    test('a flow with a liveness step waits, even before the upload has started', () {
      expect(selfieUploadExpected(idle, hasLivenessStep: true), isTrue);
    });
    test('an upload already started or failed counts whatever the step order says', () {
      expect(
        selfieUploadExpected(
          const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading),
          hasLivenessStep: false,
        ),
        isTrue,
      );
      expect(
        selfieUploadExpected(
          SelfieUploadSnapshot(selfieUpload: SelfieUploadState.failed('x')),
          hasLivenessStep: false,
        ),
        isTrue,
      );
    });
  });

  group('selfieUploadSettled', () {
    test('a finished upload, or a restored media id with nothing in flight, is settled', () {
      expect(selfieUploadSettled(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.done, selfieMediaId: 'm1')), isA<SelfieUploadOk>());
      expect(selfieUploadSettled(const SelfieUploadSnapshot(selfieUpload: kIdleSelfieUpload, selfieMediaId: 'm1')), isA<SelfieUploadOk>());
    });

    test('an upload in flight, or one not yet started, keeps the caller waiting', () {
      expect(selfieUploadSettled(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading)), isNull);
      // The media id landed but the liveness video is still going up: wait for it.
      expect(selfieUploadSettled(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading, selfieMediaId: 'm1')), isNull);
      expect(selfieUploadSettled(const SelfieUploadSnapshot(selfieUpload: kIdleSelfieUpload)), isNull);
    });

    test('a failure carries its message', () {
      final w = selfieUploadSettled(SelfieUploadSnapshot(selfieUpload: SelfieUploadState.failed('No network.')));
      expect(w, isA<SelfieUploadFailed>());
      expect((w as SelfieUploadFailed).message, 'No network.');
    });
  });

  group('awaitSelfieUpload', () {
    test('resolves at once when already settled, without subscribing', () async {
      final store = _FakeStore(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.done, selfieMediaId: 'm1'));
      expect(await awaitSelfieUpload(read: store.read, subscribe: store.subscribe), isA<SelfieUploadOk>());
      expect(store.listeners, isEmpty);
    });

    test('waits for the store to report done, then unsubscribes', () async {
      final store = _FakeStore(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading));
      final wait = awaitSelfieUpload(read: store.read, subscribe: store.subscribe);
      expect(store.listeners.length, 1);
      store.set(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading, selfieMediaId: 'm1'));
      store.set(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.done, selfieMediaId: 'm1'));
      expect(await wait, isA<SelfieUploadOk>());
      expect(store.listeners, isEmpty);
    });

    test('a failure ends the wait with its message', () async {
      final store = _FakeStore(const SelfieUploadSnapshot(selfieUpload: SelfieUploadState.uploading));
      final wait = awaitSelfieUpload(read: store.read, subscribe: store.subscribe);
      store.set(SelfieUploadSnapshot(selfieUpload: SelfieUploadState.failed('Upload failed.')));
      expect(((await wait) as SelfieUploadFailed).message, 'Upload failed.');
    });

    test('gives up at the deadline with a message the person can act on', () async {
      final store = _FakeStore(const SelfieUploadSnapshot(selfieUpload: kIdleSelfieUpload));
      final result = await awaitSelfieUpload(
        read: store.read,
        subscribe: store.subscribe,
        timeout: const Duration(milliseconds: 5),
      );
      expect(result, isA<SelfieUploadFailed>());
      final message = (result as SelfieUploadFailed).message;
      expect(message, matches(RegExp('try again', caseSensitive: false)));
      expect(message, isNot(contains('—')));
      expect(store.listeners, isEmpty);
    });
  });
}
