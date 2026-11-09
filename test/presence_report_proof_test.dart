import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/presence_report_proof.dart';
import 'package:toden_flutter/src/services/api_service.dart' show DeviceChallenge;
import 'package:toden_flutter/src/services/device_attestation.dart';
import 'package:toden_flutter/src/services/device_intel_platform.dart';

class _Native implements DeviceIntelPlatform {
  String? requestHash;
  Uint8List? clientDataHash;

  @override
  Future<String?> playIntegrityToken({required String cloudProjectNumber, required String requestHash}) async {
    this.requestHash = requestHash;
    return 'token';
  }

  @override
  Future<Map<String, dynamic>?> appAttestState() async => {'supported': true, 'keyId': 'key'};

  @override
  Future<Map<String, dynamic>?> appAttest({String? keyId, required Uint8List clientDataHash, required bool attest}) async {
    this.clientDataHash = clientDataHash;
    return {'keyId': 'key', 'assertion': 'assertion'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The vector kyc-core's report-proof.test.ts pins: every copy must agree
  // byte for byte, or the platform's proof never verifies.
  const observations = [
    ReportObservation(day: '2026-10-30', source: 'geofence', dwellMinutes: 120, nightPresent: true, samples: 3),
    ReportObservation(day: '2026-10-31', source: 'foreground', dwellMinutes: 0, nightPresent: false, samples: 1, mockLocation: true),
  ];
  final text = reportDigestText(
    externalUserId: 'user_123',
    stableId: 'stable-1',
    deviceId: 'install-1',
    observations: observations,
  );

  test('the digest matches the server vector', () {
    expect(sha256.convert(utf8.encode(text)).toString(),
        '14e467f5a1431e451564634466e45e7c3a62693f9bd026c9c19570c03cbf8640');
  });

  test('the challenge is bound the way the server binds it', () {
    final digest = sha256.convert(utf8.encode(text)).bytes;
    final expected = sha256.convert([...utf8.encode('issued'), ...digest]).toString();
    expect(sha256.convert(boundChallenge(utf8.encode('issued'), text)).toString().length, 64);
    expect(Digest(boundChallenge(utf8.encode('issued'), text)).toString(), expected);
  });

  test('a flagged observation carries its flags on the wire', () {
    expect(observations[1].toJson()['integrity'], {'mockLocation': true});
    expect(observations[0].toJson().containsKey('integrity'), false);
  });

  final challenge = DeviceChallenge.fromJson({
    'challengeId': 'c',
    'challenge': base64Encode(utf8.encode('issued')),
    'expiresAt': DateTime.now().toIso8601String(),
  });

  test('Play Integrity signs the bound challenge', () async {
    final native = _Native();
    await collectAttestation(
      platform: 'android',
      native: native,
      cloudProjectNumber: '42',
      fetchChallenge: ({required String platform, String? keyId}) async => challenge,
      bindChallenge: (c) => boundChallenge(c, text),
    );
    expect(native.requestHash, sha256.convert(boundChallenge(utf8.encode('issued'), text)).toString());
  });

  test('App Attest signs the bound challenge', () async {
    final native = _Native();
    await collectAttestation(
      platform: 'ios',
      native: native,
      fetchChallenge: ({required String platform, String? keyId}) async => challenge,
      bindChallenge: (c) => boundChallenge(c, text),
    );
    expect(native.clientDataHash, sha256.convert(boundChallenge(utf8.encode('issued'), text)).bytes);
  });
}
