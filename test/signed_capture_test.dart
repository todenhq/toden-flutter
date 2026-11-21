import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/signed_capture.dart';
import 'package:toden_flutter/src/presence/presence_report_proof.dart' show boundChallenge;

import 'device_intel_fakes.dart';

void main() {
  final selfie = 'a' * 64;
  final video = 'b' * 64;

  // The vector kyc-core's signed-capture.test.ts pins: every copy must agree
  // byte for byte, or the platform's proof never verifies.
  test('the digest matches the server vector', () {
    final text = captureDigestText({'selfie': selfie, 'livenessVideo': video});
    expect(sha256.convert(utf8.encode(text)).toString(),
        '1086b34afa90de77c7232329b065da5637e479c962c569b7c7267a0b45659a77');
  });

  // kyc-core's three-slot vector: the iPhone depth frame adds its own line.
  test('the digest with a depth frame matches the server vector', () {
    final depth = 'c' * 64;
    final text = captureDigestText(
        {'selfie': selfie, 'livenessVideo': video, 'livenessDepth': depth});
    expect(text,
        'toden-capture-v1\nselfie:$selfie\nlivenessVideo:$video\nlivenessDepth:$depth');
    expect(sha256.convert(utf8.encode(text)).toString(),
        'ec1416d3c16ad8708f250fb05d8a50bc5939490eff37a008f9381cc2dc0ab681');
  });

  test('an upload not sent is an empty line, in the same place', () {
    expect(captureDigestText({'selfie': selfie}),
        'toden-capture-v1\nselfie:$selfie\nlivenessVideo:');
  });

  test('no depth frame adds no line at all, so older proofs read the same', () {
    expect(captureDigestText({'selfie': selfie, 'livenessVideo': video, 'livenessDepth': ''}),
        'toden-capture-v1\nselfie:$selfie\nlivenessVideo:$video');
  });

  test('the depth frame is signed with the rest when the verification names it', () async {
    final depth = 'c' * 64;
    expect(
      signableUploads(
        sent: {'selfie': 'm_s', 'livenessVideo': 'm_v', 'livenessDepth': 'm_d'},
        uploaded: {
          'selfie': (mediaId: 'm_s', sha256: selfie),
          'livenessVideo': (mediaId: 'm_v', sha256: video),
          'livenessDepth': (mediaId: 'm_d', sha256: depth),
        },
      ),
      {'selfie': selfie, 'livenessVideo': video, 'livenessDepth': depth},
    );
    final native = FakeNative();
    final proof = await signCapture(
      media: {'selfie': selfie, 'livenessVideo': video, 'livenessDepth': depth},
      platform: 'ios',
      native: native,
      fetchChallenge: fetcher(),
    );
    final text = captureDigestText(
        {'selfie': selfie, 'livenessVideo': video, 'livenessDepth': depth});
    expect(native.lastHash, sha256.convert(boundChallenge(challengeBytes, text)).bytes);
    expect(proof?['media'], {'selfie': selfie, 'livenessVideo': video, 'livenessDepth': depth});
  });

  test('the upload hash is the lowercase hex SHA-256 of the bytes sent', () {
    expect(uploadSha256(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('only uploads the verification still names are signed', () {
    final uploaded = {
      'selfie': (mediaId: 'm_selfie_2', sha256: selfie),
      'livenessVideo': (mediaId: 'm_video_1', sha256: video),
    };
    expect(
      signableUploads(sent: {'selfie': 'm_selfie_2', 'livenessVideo': 'm_video_1'}, uploaded: uploaded),
      {'selfie': selfie, 'livenessVideo': video},
    );
    // A retake dropped the video and its id: the old video's hash goes with it.
    expect(
      signableUploads(sent: {'selfie': 'm_selfie_2', 'livenessVideo': null}, uploaded: uploaded),
      {'selfie': selfie},
    );
    // A restored session names an upload this run never hashed.
    expect(signableUploads(sent: {'selfie': 'm_restored', 'livenessVideo': null}, uploaded: uploaded), isEmpty);
  });

  test('App Attest signs the challenge bound to the digest', () async {
    final native = FakeNative();
    final proof = await signCapture(
      media: {'selfie': selfie, 'livenessVideo': video},
      platform: 'ios',
      native: native,
      fetchChallenge: fetcher(),
    );
    final text = captureDigestText({'selfie': selfie, 'livenessVideo': video});
    expect(native.lastHash, sha256.convert(boundChallenge(challengeBytes, text)).bytes);
    expect(proof, {
      'media': {'selfie': selfie, 'livenessVideo': video},
      'attestation': {
        'platform': 'ios',
        'kind': 'app_attest',
        'challengeId': 'ch_1',
        'keyId': 'key-1',
        'assertion': 'QVNT',
      },
    });
  });

  test('Play Integrity signs the selfie alone when no video was sent', () async {
    final native = FakeNative();
    final proof = await signCapture(
      media: {'selfie': selfie},
      platform: 'android',
      native: native,
      cloudProjectNumber: '42',
      fetchChallenge: fetcher(),
    );
    final text = captureDigestText({'selfie': selfie});
    expect(native.lastRequestHash, sha256.convert(boundChallenge(challengeBytes, text)).toString());
    expect(proof?['media'], {'selfie': selfie});
    expect(proof?['attestation'], containsPair('token', 'pi-token'));
  });

  test('no proof without an attestation: no project, no challenge, no platform', () async {
    final media = {'selfie': selfie};
    expect(await signCapture(media: media, platform: 'android', native: FakeNative(), fetchChallenge: fetcher()),
        isNull);
    expect(
        await signCapture(media: media, platform: 'ios', native: FakeNative(), fetchChallenge: fetcher(fail: true)),
        isNull);
    expect(await signCapture(media: media, platform: null, native: FakeNative(), fetchChallenge: fetcher()), isNull);
  });

  test('nothing uploaded asks the platform for nothing', () async {
    final keys = <String?>[];
    expect(
        await signCapture(media: const {}, platform: 'ios', native: FakeNative(), fetchChallenge: fetcher(keys: keys)),
        isNull);
    expect(keys, isEmpty);
  });

  test('a slow platform is cut off by the budget', () async {
    final native = FakeNative()..delay = const Duration(seconds: 2);
    final proof = await signCapture(
      media: {'selfie': selfie},
      platform: 'ios',
      native: native,
      fetchChallenge: fetcher(),
      budget: const Duration(milliseconds: 50),
    );
    expect(proof, isNull);
  });
}
