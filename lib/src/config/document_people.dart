// The people a company's own documents name, read as each document is
// uploaded, merged into the key-people list.
//
// The documents step comes before the key-people step, and a MEMART, a
// register of shareholders or an annual return already lists who runs and owns
// the company. Each such upload is read straight away (POST
// /business/documents/people) and the people it names are merged into the list
// when the answer arrives, so the applicant confirms the names and adds what
// the page did not say, usually each person's email.
//
// Pure. Mirrors the web SDK's lib/document-people.ts and the React Native SDK's
// config/documentPeople.ts: keep the three in lockstep.
import '../services/api_service.dart';
import 'business.dart';
import 'business_application.dart';
import 'business_document_groups.dart';
import 'document_people_sources.dart';
import 'key_people_prefill.dart';
import 'key_people_sections.dart';

/// The documents that record a company's people. Mirrors kyc-core's
/// PEOPLE_NAMING_DOCUMENTS (business-documents/parties.ts); the server decides
/// in the end, this only saves asking about a tax return.
const Set<String> kPeopleNamingDocuments = {
  'memart',
  'registry_extract',
  'annual_return',
  'register_of_directors',
  'shareholder_register',
  'share_certificate',
  'ubo_declaration',
  'business_registration',
};

/// Whether an upload in [group] is worth reading for its people.
bool readsDocumentPeople(
  WorkflowBusinessConfig? business,
  BusinessDocumentGroup group,
) =>
    hasKeyPeopleCollection(business) &&
    group.types.any((t) => kPeopleNamingDocuments.contains(t.key));

/// The list with a document's people merged in.
///
/// Someone already listed (the same person, by the register's name rule) gains
/// a role they did not have and fills an empty email or stake; what the
/// applicant or the register already put there is never overwritten. Anyone
/// else is added, up to the row limit. `added` counts the new rows. Each row
/// remembers the document ([mediaId]) that named it, so taking the document
/// back takes the person back (document_people_sources.dart).
({List<KeyPersonEntry> rows, int added}) mergeDocumentPeople(
  List<KeyPersonEntry> rows,
  List<RegistryOfficer> people,
  String defaultCountry,
  String mediaId,
) {
  final next = [...rows];
  var added = 0;
  for (final person in prefillKeyPeople(people, defaultCountry)) {
    final i = next.indexWhere(
        (r) => r.name.trim().isNotEmpty && samePerson(r.name, person.name));
    if (i >= 0) {
      final existing = next[i];
      final roles = {...rolesOf(existing), ...rolesOf(person)}.toList();
      final after = existing.copyWith(
        roles: roles,
        role: primaryRole(roles),
        email: existing.email.trim().isEmpty ? person.email : existing.email,
        ownershipPct: existing.ownershipPct.trim().isEmpty
            ? person.ownershipPct
            : existing.ownershipPct,
      );
      next[i] = namedByDocument(existing, after, mediaId);
      continue;
    }
    if (next.length >= kMaxKeyPeopleRows) break;
    next.add(addedByDocument(person, mediaId));
    added += 1;
  }
  return (rows: next, added: added);
}

/// How many different people the documents still uploaded named.
int documentPeopleCount(
  Map<String, List<RegistryOfficer>> documentPeople,
  Iterable<String> uploadedMediaIds,
) {
  final uploaded = uploadedMediaIds.toSet();
  final names = <String>[];
  documentPeople.forEach((mediaId, people) {
    if (!uploaded.contains(mediaId)) return;
    for (final p in people) {
      final name = (p.name ?? '').trim();
      if (name.isNotEmpty && !names.any((n) => samePerson(n, name))) {
        names.add(name);
      }
    }
  });
  return names.length;
}

/// The note while a document is being read for its people.
const String kDocumentPeopleReadingNote =
    'We are reading your company documents for the people they name. You can add people now, or they will be filled in when we finish.';

/// The note once the documents' people are in the list. Mirrors the web texts.
String documentPeopleAddedNote(int count) => count == 1
    ? 'We filled in 1 person from your company documents. Check the details and add their email so we can send their verification link.'
    : "We filled in $count people from your company documents. Check the details and add each person's email so we can send their verification link.";

/// The note when people from a removed document were kept because the
/// applicant changed them.
String documentPeopleKeptNote(int count) => count == 1
    ? '1 person came from a document you removed. We kept them because you had changed their details. Check they still belong.'
    : '$count people came from a document you removed. We kept them because you had changed their details. Check they still belong.';

/// The line on a card kept from a removed document.
const String kDocumentRemovedCardNote =
    'From a document you removed. Check they belong.';

/// The full-step reading screen's words. Mirrors the web texts.
const String kReadingTitle = 'Reading your company documents';
const String kReadingDescription =
    "We're finding the people your documents name, so you only need to check them and add their emails.";
const List<String> kReadingStages = [
  'Looking for the directors',
  'Looking for the shareholders and their stakes',
  'Checking the names belong to your company',
];
const String kReadingSlow =
    'Long documents take a little longer. If it runs on, the list opens in a moment and the people are added when we finish.';

/// A read that runs this long gives way to the list; its people merge when it lands.
const Duration kReadingGiveUp = Duration(seconds: 60);

/// "Found N people", the reading screen's last line and the notice's title.
String documentPeopleFoundTitle(int count) =>
    count == 1 ? 'Found 1 person' : 'Found $count people';
