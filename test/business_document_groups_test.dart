import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/business_document_groups.dart';

// One document per group. These vectors are copied from the web SDK's
// business-document-groups.test.ts, which mirrors kyc-core's.

WorkflowBusinessConfig business(List<Map<String, dynamic>> types) =>
    WorkflowBusinessConfig.fromJson({
      'country': 'NG',
      'documents': {'enabled': true, 'types': types},
    });

BusinessDocumentUpload up(String type, [String mediaId = 'm']) =>
    BusinessDocumentUpload(type: type, mediaId: mediaId, fileName: '$type.pdf');

void main() {
  group('businessDocumentGroups', () {
    test('groups the ticked documents in group order, keeping the workflow order inside a group', () {
      final groups = businessDocumentGroups(business([
        {'key': 'annual_return'},
        {'key': 'registry_extract', 'required': true},
        {'key': 'incorporation_certificate'},
        {'key': 'memart'},
      ]));
      expect(groups.map((g) => g.key), ['legal_presence', 'company_details']);
      expect(groups[0].types.map((t) => t.key), ['registry_extract', 'incorporation_certificate']);
      expect(groups[0].title, 'Legal presence');
      expect(groups[0].required, isTrue);
      expect(groups[1].required, isFalse);
    });

    test('carries how recent each document must be', () {
      final groups = businessDocumentGroups(business([
        {'key': 'proof_of_address', 'maxAgeMonths': 3},
        {'key': 'memart'},
      ]));
      expect(groups.map((g) => g.types.single.maxAgeMonths), [null, 3]);
    });

    test('titles the other group with the name the organisation wrote', () {
      final groups = businessDocumentGroups(business([
        {'key': 'other', 'label': 'Council tax letter'},
      ]));
      expect(groups.single.title, 'Council tax letter');
    });

    test('defaults to a required certificate of incorporation, and nothing when documents are off', () {
      final groups = businessDocumentGroups(WorkflowBusinessConfig.fromJson({
        'country': 'NG',
        'documents': {'enabled': true},
      }));
      expect(
        groups.map((g) => [g.key, g.required, g.types.map((t) => t.key).toList()]),
        [
          ['legal_presence', true, ['incorporation_certificate']],
        ],
      );
      expect(businessDocumentGroups(WorkflowBusinessConfig.fromJson({'country': 'NG'})), isEmpty);
    });

    test('puts every catalogue document in a known group', () {
      for (final group in kBusinessDocumentGroupOf.values) {
        expect(kBusinessDocumentGroupOrder, contains(group));
      }
      // And every catalogue document has a label (older builds showed raw keys).
      for (final key in kBusinessDocumentGroupOf.keys) {
        expect(kBusinessDocumentLabels[key], isNotNull, reason: key);
      }
    });
  });

  group('moving through the groups', () {
    final groups = businessDocumentGroups(business([
      {'key': 'incorporation_certificate', 'required': true},
      {'key': 'registry_extract'},
      {'key': 'memart'},
    ]));
    final legal = groups[0];
    final details = groups[1];

    test('holds one document per group: a second upload replaces the first', () {
      final one = withGroupUpload(legal, const [], up('incorporation_certificate', 'm1'));
      final two = withGroupUpload(legal, one, up('registry_extract', 'm2'));
      expect(two.map((u) => [u.type, u.mediaId]), [
        ['registry_extract', 'm2'],
      ]);
    });

    test('replaces a group upload made without a chosen type', () {
      BusinessDocumentUpload byGroup(String mediaId) => BusinessDocumentUpload(
          type: 'incorporation_certificate',
          group: 'legal_presence',
          mediaId: mediaId,
          fileName: 'legal_presence.jpg');
      final one = withGroupUpload(legal, const [], byGroup('m1'));
      final two = withGroupUpload(legal, one, byGroup('m2'));
      expect(two.map((u) => [u.group, u.mediaId]), [
        ['legal_presence', 'm2'],
      ]);
      expect(withoutGroupUpload(legal, two), isEmpty);
    });

    test('an upload from before recognition still fills its group by its type', () {
      expect(groupUpload(legal, [up('registry_extract')])?.type, 'registry_extract');
      expect(groupUpload(details, [up('registry_extract')]), isNull);
    });

    test('sends a group upload by its group, and an older one by its type', () {
      expect(
        const BusinessDocumentUpload(
          type: 'incorporation_certificate',
          group: 'legal_presence',
          mediaId: 'm1',
          fileName: 'a.pdf',
        ).toJson(),
        {'group': 'legal_presence', 'mediaId': 'm1'},
      );
      expect(up('memart', 'm2').toJson(), {'type': 'memart', 'mediaId': 'm2'});
    });

    test('lets an optional group be skipped and holds a required one until it has a document', () {
      expect(canLeaveGroup(legal, const []), isFalse);
      expect(canLeaveGroup(legal, [up('registry_extract')]), isTrue);
      expect(canLeaveGroup(details, const []), isTrue);
    });

    test('opens on the first group with nothing uploaded, else the last group', () {
      expect(firstOpenGroupIndex(groups, const []), 0);
      expect(firstOpenGroupIndex(groups, [up('incorporation_certificate')]), 1);
      expect(firstOpenGroupIndex(groups, [up('incorporation_certificate'), up('memart')]), 1);
    });
  });

  group('a refused submission names what is missing', () {
    test('names the groups when the server sends them', () {
      expect(
        missingDocumentsMessage({
          'missing': ['incorporation_certificate', 'registry_extract'],
          'missingGroups': ['legal_presence'],
        }),
        'Required business documents are missing: Legal presence. Please go back and upload them.',
      );
    });

    test('falls back to the document labels from an older server', () {
      expect(
        missingDocumentsMessage({
          'missing': ['memart'],
        }),
        contains('Memorandum and articles / company constitution'),
      );
      expect(missingDocumentsMessage(null), contains('go back'));
    });
  });
}
