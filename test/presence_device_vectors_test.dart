import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:toden_flutter/src/presence/presence_device.dart';
import 'package:toden_flutter/src/presence/presence_report_proof.dart';

// The shared presence device cases (test/presence_seal_vectors.json), replayed
// here as the RN, XCTest and JVM suites replay them.

ReportObservation _observation(Map<String, dynamic> o) {
  final integrity = (o['integrity'] as Map?) ?? const {};
  return ReportObservation(
    day: o['day'] as String,
    source: o['source'] as String,
    dwellMinutes: o['dwellMinutes'] as int,
    nightPresent: o['nightPresent'] as bool,
    samples: o['samples'] as int,
    mockLocation: integrity['mockLocation'] == true,
    emulator: integrity['emulator'] == true,
  );
}

BigInt _int(Uint8List bytes) =>
    bytes.fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));

/// ECDSA-SHA256 over [text] with a DER signature and an X9.63 P-256 point.
bool _verifies(String x963, String text, String derSignature) {
  final curve = ECCurve_secp256r1();
  final point = curve.curve.decodePoint(base64Decode(x963))!;
  final seq =
      ASN1Parser(base64Decode(derSignature)).nextObject() as ASN1Sequence;
  final r = (seq.elements![0] as ASN1Integer).integer!;
  final s = (seq.elements![1] as ASN1Integer).integer!;
  final signer = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter(ECPublicKey(point, curve)));
  return signer.verifySignature(
      Uint8List.fromList(utf8.encode(text)), ECSignature(r, s));
}

void main() {
  final doc =
      jsonDecode(File('test/presence_seal_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  List<Map<String, dynamic>> cases(String key) =>
      (doc[key] as List).cast<Map<String, dynamic>>();

  test('uses the same intervals and SPKI prefix', () {
    expect(kPresenceRefreshIntervalMillis, doc['refreshIntervalMillis']);
    expect(kPresenceBackOffMillis, doc['backOffMillis']);
    expect(kP256SpkiPrefixHex, doc['spkiPrefixHex']);
    final key = doc['key'] as Map<String, dynamic>;
    final spki = base64Decode(key['spki'] as String);
    final prefix = spki
        .sublist(0, 26)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(prefix, kP256SpkiPrefixHex);
    expect(base64Encode(spki.sublist(26)), key['x963']);
    expect(_int(spki.sublist(26, 27)), BigInt.from(4),
        reason: 'an uncompressed point');
  });

  test('a signature in the shared format verifies, and a changed text does not',
      () {
    final sig = doc['signature'] as Map<String, dynamic>;
    final x963 = (doc['key'] as Map<String, dynamic>)['x963'] as String;
    expect(_verifies(x963, sig['text'] as String, sig['signature'] as String),
        isTrue);
    expect(
        _verifies(
            x963, sig['tamperedText'] as String, sig['signature'] as String),
        isFalse);
  });

  test("core's own signatures verify over the texts this SDK builds", () {
    final c = doc['core'] as Map<String, dynamic>;
    final spki = base64Decode(c['publicKey'] as String);
    final x963 = base64Encode(spki.sublist(26));
    final reg = c['registration'] as Map<String, dynamic>;
    final registration = presenceRegistrationText(
        reg['externalUserId'], c['publicKey'], reg['signedAt']);
    expect(registration, reg['text']);
    expect(_verifies(x963, registration, reg['signature'] as String), isTrue);
    final ref = c['refresh'] as Map<String, dynamic>;
    final refresh = presenceRefreshText(
        ref['deviceId'], ref['externalUserId'], ref['signedAt']);
    expect(refresh, ref['text']);
    expect(_verifies(x963, refresh, ref['signature'] as String), isTrue);
    final s = c['seal'] as Map<String, dynamic>;
    final seal = presenceSealText(
        s['deviceId'],
        s['externalUserId'],
        _observation((s['observation'] as Map).cast<String, dynamic>()),
        s['observedAtMillis']);
    expect(seal, s['text']);
    expect(_verifies(x963, seal, s['signature'] as String), isTrue);
  });

  group('texts', () {
    for (final c in cases('registration')) {
      test('registration for ${c['externalUserId']}', () {
        expect(
            presenceRegistrationText(
                c['externalUserId'], c['publicKey'], c['signedAt']),
            c['text']);
      });
    }
    for (final c in cases('refresh')) {
      test('refresh for ${c['externalUserId']}', () {
        expect(
            presenceRefreshText(
                c['deviceId'], c['externalUserId'], c['signedAt']),
            c['text']);
      });
    }
    for (final c in cases('seal')) {
      test('seal: ${c['name']}', () {
        final o =
            _observation((c['observation'] as Map).cast<String, dynamic>());
        expect(
            presenceSealText(
                c['deviceId'], c['externalUserId'], o, c['observedAtMillis']),
            c['text']);
        expect(
          DateTime.fromMillisecondsSinceEpoch(c['observedAtMillis'] as int,
                  isUtc: true)
              .toIso8601String(),
          c['observedAt'],
        );
      });
    }
  });

  group('rules', () {
    for (final c in cases('signedAt')) {
      test(
          'signedAt: ${c['name']}',
          () => expect(
              nextSignedAt(c['correctedNow'], c['lastSent']), c['expected']));
    }
    for (final c in cases('clockOffset')) {
      test(
          'clock: ${c['name']}',
          () => expect(
              clockOffsetFrom(c['date'], c['deviceNowMillis']), c['expected']));
    }
    for (final c in cases('refreshAnswers')) {
      test('refresh answer: ${c['name']}', () {
        final want = {
          'store': PresenceRefreshOutcome.store,
          'delete_key': PresenceRefreshOutcome.deleteKey,
          'retry_clock': PresenceRefreshOutcome.retryClock,
          'retry_signed_at': PresenceRefreshOutcome.retrySignedAt,
          'back_off': PresenceRefreshOutcome.backOff,
          'keep': PresenceRefreshOutcome.keep,
        }[c['outcome']];
        expect(presenceRefreshOutcome(c['status'], c['code']), want);
      });
    }
    for (final c in cases('registrationAnswers')) {
      test('registration answer: ${c['name']}', () {
        final want = {
          'registered': PresenceRegistrationOutcome.registered,
          'refused': PresenceRegistrationOutcome.refused,
          'limit': PresenceRegistrationOutcome.limit,
          'delete_key': PresenceRegistrationOutcome.deleteKey,
          'retry_clock': PresenceRegistrationOutcome.retryClock,
          'keep': PresenceRegistrationOutcome.keep,
        }[c['outcome']];
        expect(presenceRegistrationOutcome(c['status'], c['code']), want);
      });
    }
    for (final c in cases('refreshDue')) {
      test('refresh due: ${c['name']}', () {
        expect(
            presenceRefreshDue(c['nowMillis'], c['lastRefreshAtMillis'],
                c['backOffUntilMillis']),
            c['due']);
      });
    }
    for (final c in cases('heldWatch')) {
      test('held watch: ${c['name']}', () {
        expect(
            removableAfterSend(
                (c['sent'] as List).cast<String>(), c['deadlineDay']),
            c['removed']);
      });
    }
  });
}
