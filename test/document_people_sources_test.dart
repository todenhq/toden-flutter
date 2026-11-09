import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/business_application.dart';
import 'package:toden_flutter/src/config/document_people.dart';
import 'package:toden_flutter/src/config/document_people_sources.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// Taking a removed document's people back out. Mirrors the web SDK's
// lib/document-people-sources.test.ts and the React Native SDK's
// __tests__/documentPeopleSources.test.ts.
void main() {
  RegistryOfficer officer(String name, [String designation = 'DIRECTOR']) =>
      RegistryOfficer(name: name, designation: designation);
  const typed = KeyPersonEntry(name: 'Ama Mensah', country: 'GH');

  test(
      'removes the people a removed document added, and leaves the applicant’s own rows',
      () {
    final merged =
        mergeDocumentPeople([typed], [officer('Kofi Boateng')], 'GH', 'med_1')
            .rows;
    final out = withoutRemovedDocuments(merged, {});
    expect(out.rows.map((r) => r.name), ['Ama Mensah']);
    expect(out.removed, 1);
    expect(out.kept, 0);
  });

  test('keeps a person the applicant changed, flagged for them to check', () {
    final merged =
        mergeDocumentPeople([], [officer('Kofi Boateng')], 'GH', 'med_1').rows;
    final edited = [
      for (final r in merged) r.copyWith(email: 'kofi@example.com')
    ];
    final out = withoutRemovedDocuments(edited, {});
    expect(out.rows, hasLength(1));
    expect(out.rows.single.documentRemoved, isTrue);
    expect(out.rows.single.sourceDocuments, isEmpty);
    expect(out.kept, 1);
  });

  test('keeps a person while another uploaded document still names them', () {
    var rows =
        mergeDocumentPeople([], [officer('Kofi Boateng')], 'GH', 'med_1').rows;
    rows = mergeDocumentPeople(
            rows, [officer('Kofi Boateng', 'SHAREHOLDER')], 'GH', 'med_2')
        .rows;
    final out = withoutRemovedDocuments(rows, {'med_2'});
    expect(out.rows.single.sourceDocuments, ['med_2']);
  });

  test(
      'does not count the fill-in from a second document as the applicant’s edit',
      () {
    var rows =
        mergeDocumentPeople([], [officer('Kofi Boateng')], 'GH', 'med_1').rows;
    rows = mergeDocumentPeople(
            rows,
            [
              const RegistryOfficer(
                  name: 'Kofi Boateng',
                  designation: 'SHAREHOLDER',
                  email: 'k@x.example')
            ],
            'GH',
            'med_2')
        .rows;
    expect(withoutRemovedDocuments(rows, {}).rows, isEmpty);
  });

  test('returns the same list when nothing a document added is affected', () {
    final rows =
        mergeDocumentPeople([], [officer('Kofi Boateng')], 'GH', 'med_1').rows;
    expect(
        identical(withoutRemovedDocuments(rows, {'med_1'}).rows, rows), isTrue);
  });

  test('a replacement document naming a kept person clears the flag', () {
    final merged =
        mergeDocumentPeople([], [officer('Kofi Boateng')], 'GH', 'med_1').rows;
    final kept = withoutRemovedDocuments(
        [for (final r in merged) r.copyWith(email: 'k@x.example')], {}).rows;
    final again =
        mergeDocumentPeople(kept, [officer('Kofi Boateng')], 'GH', 'med_9')
            .rows;
    expect(again.single.documentRemoved, isFalse);
    expect(again.single.sourceDocuments, ['med_9']);
  });
}
