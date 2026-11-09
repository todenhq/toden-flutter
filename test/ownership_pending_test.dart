import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/key_people_sections.dart';
import 'package:toden_flutter/src/config/ownership_pending.dart';
import 'package:toden_flutter/src/providers/awaiting_people.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// ─── Shareholders the register has not sent yet ──────────────────────────────
//
// A register read through Didit can take minutes to send the shareholders; the
// server adds them to the application when they arrive. A missing field is an
// older server and reads as false. Mirrors the web and React Native tests.

AwaitingPerson _person(String status) =>
    AwaitingPerson(id: 'kp_$status', name: 'Ada', role: 'director', status: status);

class _Api extends VerificationApiService {
  _Api(this.answer) : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final SessionSummaryResponse answer;

  @override
  Future<SessionSummaryResponse> sessionSummary(String sessionId) async => answer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the register check at selection', () {
    test('reads ownershipPending off the business block, missing as false', () {
      BusinessSelectResponse parse(Map<String, dynamic> business) =>
          BusinessSelectResponse.fromJson({
            'checked': true,
            'found': true,
            'business': {'registrationNumber': 'RC1', 'keyPeople': [], ...business},
          });
      expect(parse({'ownershipPending': true}).ownershipPending, isTrue);
      expect(parse({'ownershipPending': false}).ownershipPending, isFalse);
      expect(parse({}).ownershipPending, isFalse);
      expect(parse({'ownershipPending': 'true'}).ownershipPending, isFalse);
      expect(
        BusinessSelectResponse.fromJson({'checked': false}).ownershipPending,
        isFalse,
      );
    });
  });

  group('the completed-session summary', () {
    test('reads keyPeopleOwnershipPending, missing as false', () {
      SessionSummaryResponse parse(Map<String, dynamic> extra) =>
          SessionSummaryResponse.fromJson({'keyPeople': [], ...extra});
      expect(parse({'keyPeopleOwnershipPending': true}).keyPeopleOwnershipPending, isTrue);
      expect(parse({'keyPeopleOwnershipPending': false}).keyPeopleOwnershipPending, isFalse);
      expect(parse({}).keyPeopleOwnershipPending, isFalse);
    });

    test('keeps re-reading while anybody owes a check or owners are still coming', () {
      final done = [_person('verified'), _person('not_needed')];
      expect(keepReadingSummary(done, false), isFalse);
      expect(keepReadingSummary(done, true), isTrue);
      expect(keepReadingSummary(const [], true), isTrue);
      expect(keepReadingSummary([_person('pending')], false), isTrue);
      expect(keepReadingSummary([_person('submitted')], false), isTrue);
      expect(keepReadingSummary([_person('failed')], false), isTrue);
    });

    test('the success screen controller exposes the flag once settled', () async {
      final c = AwaitingPeopleController(
        api: _Api(const SessionSummaryResponse(
          keyPeopleSettled: true,
          keyPeople: [],
          keyPeopleOwnershipPending: true,
        )),
        sessionId: 'sess_1',
      );
      addTearDown(c.dispose);
      expect(c.ownershipPending, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.finished, isTrue);
      expect(c.people, isEmpty);
      expect(c.ownershipPending, isTrue);
    });
  });

  group('the key-people step', () {
    test('puts the note in Shareholders, else Beneficial owners, else nowhere', () {
      expect(
        ownershipNoteSection(const [
          KeyPeopleSection.ubos,
          KeyPeopleSection.shareholders,
          KeyPeopleSection.representatives,
        ]),
        KeyPeopleSection.shareholders,
      );
      expect(
        ownershipNoteSection(const [KeyPeopleSection.ubos, KeyPeopleSection.representatives]),
        KeyPeopleSection.ubos,
      );
      expect(ownershipNoteSection(const [KeyPeopleSection.representatives]), isNull);
    });
  });

  group('the notes', () {
    test('carry no em dashes', () {
      expect(kOwnershipPendingStepNote, isNot(contains('—')));
      expect(kOwnershipPendingSubmittedNote, isNot(contains('—')));
    });

    const web = [
      '../sdk-react/src/i18n/groups/keyPeople-step.ts',
      '../sdk-react/src/i18n/groups/keyPeople-await.ts',
    ];
    final present = web.every((p) => File(p).existsSync());
    test('match the web SDK word for word', () {
      final source = web.map((p) => File(p).readAsStringSync()).join();
      expect(source, contains(kOwnershipPendingStepNote));
      expect(source, contains(kOwnershipPendingSubmittedNote));
    }, skip: present ? false : 'needs the monorepo: the web SDK is not here');
  });
}
