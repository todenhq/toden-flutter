import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/business.dart';
import 'package:toden_flutter/src/config/business_application.dart';
import 'package:toden_flutter/src/config/business_document_groups.dart';
import 'package:toden_flutter/src/config/document_people.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// Mirrors the web SDK's lib/document-people.test.ts and the React Native SDK's
// __tests__/documentPeople.test.ts.
void main() {
  const people = [
    RegistryOfficer(name: 'Ama Mensah', designation: 'DIRECTOR', ownershipPct: 60),
    RegistryOfficer(
        name: 'Kofi Boateng',
        designation: 'SHAREHOLDER',
        ownershipPct: 40,
        email: 'kofi@example.com'),
  ];

  BusinessDocumentGroup group(String key) => BusinessDocumentGroup(
        key: 'company_details',
        title: 'Company details',
        types: [BusinessDocumentGroupType(key: key, label: key)],
        required: false,
      );

  test('reads only people-naming groups on a workflow that collects key people', () {
    const business = WorkflowBusinessConfig(
        country: 'GH',
        keyPeople: WorkflowKeyPeopleConfig(enabled: true, collect: true));
    expect(readsDocumentPeople(business, group('memart')), isTrue);
    expect(readsDocumentPeople(business, group('tax_document')), isFalse);
    const noCollect = WorkflowBusinessConfig(
        country: 'GH', keyPeople: WorkflowKeyPeopleConfig(enabled: true));
    expect(readsDocumentPeople(noCollect, group('memart')), isFalse);
  });

  test('adds new people and fills only what is missing on someone already listed', () {
    const rows = [
      KeyPersonEntry(
          name: 'AMA MENSAH',
          role: KeyPersonRole.director,
          email: 'ama@own.example',
          ownershipPct: '55',
          country: 'GH'),
    ];
    final merged = mergeDocumentPeople(rows, people, 'GH', 'med_1');
    expect(merged.added, 1);
    expect(merged.rows, hasLength(2));
    expect(merged.rows[0].email, 'ama@own.example');
    expect(merged.rows[0].ownershipPct, '55');
    expect(merged.rows[1].name, 'Kofi Boateng');
    expect(merged.rows[1].email, 'kofi@example.com');
    expect(merged.rows[1].ownershipPct, '40');
  });

  test('counts the people named by documents still uploaded', () {
    expect(documentPeopleCount({'med_1': people}, ['med_1']), 2);
    expect(documentPeopleCount({'med_1': people}, const []), 0);
  });
}
