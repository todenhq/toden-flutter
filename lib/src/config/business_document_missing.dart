import '../i18n/translate.dart';
import 'business.dart';
import 'business_document_groups.dart';

// ─── A refused submission names the missing company documents ────────────────
//
// Split from business_document_groups.dart (which re-exports it) to keep that
// file within the 200-line rule. Mirrors the web SDK's missing-documents text.

/// The message for a 422 `missing_documents`: a server that asks one document
/// per group names the groups (`missingGroups`); an older one names each
/// document (`missing`).
String missingDocumentsMessage(Map<String, dynamic>? details,
    [TextFn t = defaultText]) {
  List<String> strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList() : const [];
  final groupLabels = [
    for (final key in strings(details?['missingGroups']))
      if (businessDocumentGroupTitle(key, t) case final title?) title,
  ];
  final labels = groupLabels.isNotEmpty
      ? groupLabels
      : strings(details?['missing']).map(businessDocumentLabel).toList();
  return labels.isEmpty
      ? t('general.error.missingDocuments')
      : t('general.error.missingDocumentsNamed',
          vars: {'documents': labels.join(', ')});
}
