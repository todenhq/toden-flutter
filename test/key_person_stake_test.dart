import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/business.dart';
import 'package:toden_flutter/src/config/business_application.dart';
import 'package:toden_flutter/src/config/key_person_stake.dart';

// Mirrors the web SDK's key-person-stake.test.ts.
void main() {
  const shareholder = KeyPersonEntry(name: 'Ama Mensah', role: KeyPersonRole.shareholder, roles: [KeyPersonRole.shareholder]);

  test('stakes are required by default and off when the workflow says so', () {
    WorkflowBusinessConfig cfg(Map<String, dynamic> kp) =>
        WorkflowBusinessConfig.fromJson({'country': 'NG', 'keyPeople': kp});
    expect(keyPeopleRequireOwnership(cfg({'enabled': true, 'collect': true})), isTrue);
    expect(keyPeopleRequireOwnership(cfg({'enabled': true, 'collect': true, 'requireOwnership': false})), isFalse);
    expect(keyPeopleRequireOwnership(cfg({'enabled': true})), isFalse);
  });

  test('blocks a shareholder or beneficial owner without one, never a director', () {
    expect(rowMissingStake(shareholder, true), isTrue);
    expect(rowMissingStake(shareholder.copyWith(ownershipPct: '30'), true), isFalse);
    expect(rowMissingStake(shareholder.copyWith(role: KeyPersonRole.director, roles: [KeyPersonRole.director]), true), isFalse);
    expect(rowMissingStake(shareholder, false), isFalse);
    expect(shareholder.isValidWith(const {}, stakeRequired: true), isFalse);
    expect(shareholder.isValidWith(const {}), isTrue);
  });

  test("asks a company for each named owner's share", () {
    final corp = shareholder.copyWith(isCorporate: true, ownershipPct: '40', owners: const [KeyPersonOwnerEntry(name: 'Kwame')]);
    expect(rowMissingStake(corp, true), isTrue);
  });
}
