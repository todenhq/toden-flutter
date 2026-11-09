import '../i18n/translate.dart';
import 'business.dart';
import 'business_application.dart';

export 'business_document_missing.dart';

// ─── Business documents, one per GROUP ───────────────────────────────────────
//
// Company documents are asked for one per group (Didit's model): the documents
// an organisation ticks inside one group are alternatives, and the applicant
// uploads whichever one they hold. A group is required when any document in it
// is required. The step walks the groups one at a time.
//
// MIRRORS kyc-core's src/lib/workflows/business-document-groups.ts (and its
// BUSINESS_DOCUMENT_GROUPS / BUSINESS_DOCUMENT_GROUP_OF), the web SDK's
// lib/business-document-groups.ts and the React Native SDK's
// config/businessDocumentGroups.ts. Change all four together.

/// The groups in the order they are asked for.
const List<String> kBusinessDocumentGroupOrder = [
  'legal_presence',
  'company_details',
  'ownership',
  'representative_authorisation',
  'address',
  'financial',
  'tax',
  'regulatory',
  'other',
];

/// Which group each document belongs to. A key this build does not know is
/// 'other'.
const Map<String, String> kBusinessDocumentGroupOf = {
  'incorporation_certificate': 'legal_presence',
  'business_registration': 'legal_presence',
  'good_standing_certificate': 'legal_presence',
  'registry_extract': 'legal_presence',
  'memart': 'company_details',
  'annual_return': 'company_details',
  'register_of_directors': 'ownership',
  'shareholder_register': 'ownership',
  'share_certificate': 'ownership',
  'ubo_declaration': 'ownership',
  'board_resolution': 'representative_authorisation',
  'power_of_attorney': 'representative_authorisation',
  'authorization_letter': 'representative_authorisation',
  'proof_of_address': 'address',
  'financial_statements': 'financial',
  'tax_document': 'tax',
  'regulatory_license': 'regulatory',
  'other': 'other',
};

const Map<String, String> _groupTextKeys = {
  'legal_presence': 'business.documents.group.legalPresence',
  'company_details': 'business.documents.group.companyDetails',
  'ownership': 'business.documents.group.ownership',
  'representative_authorisation':
      'business.documents.group.representativeAuthorisation',
  'address': 'business.documents.group.address',
  'financial': 'business.documents.group.financial',
  'tax': 'business.documents.group.tax',
  'regulatory': 'business.documents.group.regulatory',
  'other': 'business.documents.group.other',
};

/// A group's display title, or null for a group this build does not know.
String? businessDocumentGroupTitle(String key, [TextFn t = defaultText]) {
  final textKey = _groupTextKeys[key];
  return textKey == null ? null : t(textKey);
}

/// One document that satisfies a group.
class BusinessDocumentGroupType {
  final String key;
  final String label;

  /// How recent it must be, in months; null = any date.
  final int? maxAgeMonths;
  const BusinessDocumentGroupType(
      {required this.key, required this.label, this.maxAgeMonths});
}

/// One group the step asks for.
class BusinessDocumentGroup {
  final String key;
  final String title;

  /// The documents that satisfy the group, in the order the workflow lists them.
  final List<BusinessDocumentGroupType> types;
  final bool required;

  const BusinessDocumentGroup({
    required this.key,
    required this.title,
    required this.types,
    required this.required,
  });

  bool accepts(String type) => types.any((t) => t.key == type);

  /// Whether [upload] fills this group: it was uploaded for it, or (restored
  /// from before recognition) it names one of the group's documents.
  bool holds(BusinessDocumentUpload upload) =>
      upload.group == key || accepts(upload.type);
}

/// The groups this flow asks for, in order. Empty when documents are off.
List<BusinessDocumentGroup> businessDocumentGroups(
  WorkflowBusinessConfig? business, [
  TextFn t = defaultText,
]) {
  final slots = resolveBusinessDocumentTypes(business);
  final groups = <BusinessDocumentGroup>[];
  for (final key in kBusinessDocumentGroupOrder) {
    final inGroup = slots
        .where((s) => (kBusinessDocumentGroupOf[s.key] ?? 'other') == key)
        .toList(growable: false);
    if (inGroup.isEmpty) continue;
    // The 'other' group holds one document whose name the organisation wrote,
    // so that name is a better title than "Other documents".
    final title = key == 'other' && inGroup.length == 1
        ? inGroup.first.label
        : t(_groupTextKeys[key]!);
    groups.add(BusinessDocumentGroup(
      key: key,
      title: title,
      types: [
        for (final s in inGroup)
          BusinessDocumentGroupType(
              key: s.key, label: s.label, maxAgeMonths: s.maxAgeMonths),
      ],
      required: inGroup.any((s) => s.required),
    ));
  }
  return groups;
}

/// The upload that satisfies a group, if there is one.
BusinessDocumentUpload? groupUpload(
  BusinessDocumentGroup group,
  List<BusinessDocumentUpload> uploads,
) {
  for (final u in uploads) {
    if (group.holds(u)) return u;
  }
  return null;
}

/// Where the step opens: the first group with no upload, else the last group.
int firstOpenGroupIndex(
  List<BusinessDocumentGroup> groups,
  List<BusinessDocumentUpload> uploads,
) {
  final open = groups.indexWhere((g) => groupUpload(g, uploads) == null);
  if (open != -1) return open;
  return groups.isEmpty ? 0 : groups.length - 1;
}

/// The uploads after adding one: a group holds one document, so an upload
/// replaces whatever the same group already had.
List<BusinessDocumentUpload> withGroupUpload(
  BusinessDocumentGroup group,
  List<BusinessDocumentUpload> uploads,
  BusinessDocumentUpload upload,
) =>
    [...uploads.where((u) => !group.holds(u)), upload];

/// The uploads after clearing a group.
List<BusinessDocumentUpload> withoutGroupUpload(
  BusinessDocumentGroup group,
  List<BusinessDocumentUpload> uploads,
) =>
    uploads.where((u) => !group.holds(u)).toList(growable: false);

/// Whether the applicant may move past a group.
bool canLeaveGroup(
  BusinessDocumentGroup group,
  List<BusinessDocumentUpload> uploads,
) =>
    !group.required || groupUpload(group, uploads) != null;
