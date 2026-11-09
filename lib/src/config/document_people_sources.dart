// Which company document put a person in the key-people list, so taking the
// document back takes its people back too.
//
// An applicant can upload a MEMART, see its people filled in, then go back and
// replace or remove it. The people of a file they took back must not stay in
// the list as if the company had declared them. So a row a document added
// remembers the document (sourceDocuments) and how it looked when added
// (documentSnapshot). When documents change:
//   - a person named by another document still uploaded stays;
//   - a person whose documents are all gone is removed, unless the applicant
//     changed them since: that row stays, flagged documentRemoved, and the
//     step asks them to check it still belongs.
// A row the applicant or the register added is never touched.
//
// Pure. Mirrors the web SDK's lib/document-people-sources.ts and the React
// Native SDK's config/documentPeopleSources.ts: keep the three in lockstep.
import 'dart:convert';

import 'business.dart';
import 'business_application.dart';

/// What the applicant can change on a row, as one string, to tell an edit apart.
String rowFingerprint(KeyPersonEntry row) {
  final roles = (row.roles.isEmpty ? [row.role] : row.roles)
      .map((r) => r.key)
      .toList()
    ..sort();
  return jsonEncode([
    row.name.trim(),
    roles,
    row.title.trim(),
    row.email.trim(),
    row.country.trim().toUpperCase(),
    row.ownershipPct.trim(),
    row.isCorporate,
    row.registrationNumber.trim(),
    [
      for (final o in row.owners)
        [o.name.trim(), o.ownershipPct.trim(), o.email.trim(), o.country.trim()]
    ],
  ]);
}

/// Whether the applicant has changed a document's row since it was added.
bool editedSinceDocument(KeyPersonEntry row) =>
    row.documentSnapshot != null && rowFingerprint(row) != row.documentSnapshot;

/// A row a document has just added, remembering the document and its first form.
KeyPersonEntry addedByDocument(KeyPersonEntry row, String mediaId) {
  final next = row.copyWith(sourceDocuments: [mediaId], documentRemoved: false);
  return next.copyWith(documentSnapshot: rowFingerprint(next));
}

/// An existing row another document also names. A document's row gains the
/// document (so it stays while either is uploaded) and, when the applicant had
/// not changed it, a fresh snapshot of what the merge filled in. A row the
/// applicant typed keeps no provenance: it was theirs before any document.
KeyPersonEntry namedByDocument(
    KeyPersonEntry before, KeyPersonEntry after, String mediaId) {
  if (before.sourceDocuments.isEmpty && !before.documentRemoved) return after;
  final keepSnapshot = editedSinceDocument(before) || before.documentRemoved;
  final next = after.copyWith(
    sourceDocuments: {...before.sourceDocuments, mediaId}.toList(),
    documentRemoved: false,
  );
  return keepSnapshot
      ? next.copyWith(documentSnapshot: before.documentSnapshot)
      : next.copyWith(documentSnapshot: rowFingerprint(next));
}

/// The list after documents were removed or replaced: [uploaded] is every
/// document still in the application. `rows` is identical to the input when
/// nothing the documents added is affected.
({List<KeyPersonEntry> rows, int removed, int kept}) withoutRemovedDocuments(
  List<KeyPersonEntry> rows,
  Set<String> uploaded,
) {
  var removed = 0;
  var kept = 0;
  var changed = false;
  final next = <KeyPersonEntry>[];
  for (final row in rows) {
    final sources = row.sourceDocuments;
    if (sources.isEmpty) {
      next.add(row);
      continue;
    }
    final remaining = sources.where(uploaded.contains).toList();
    if (remaining.length == sources.length) {
      next.add(row);
      continue;
    }
    changed = true;
    if (remaining.isNotEmpty) {
      next.add(row.copyWith(sourceDocuments: remaining));
    } else if (editedSinceDocument(row)) {
      kept += 1;
      next.add(row.copyWith(sourceDocuments: const [], documentRemoved: true));
    } else {
      removed += 1;
    }
  }
  return (rows: changed ? next : rows, removed: removed, kept: kept);
}
