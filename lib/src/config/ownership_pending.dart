import '../services/api_service.dart' show AwaitingPerson;
import 'key_people_sections.dart' show KeyPeopleSection;

// Shareholders the register has not sent yet. Mirrors the web SDK's
// lib/ownership-pending.ts and the React Native SDK's
// config/ownershipPending.ts: keep the three in lockstep.
//
// Some registers (read through Didit) take minutes to answer for a company's
// shareholders. The server waits briefly when the company is picked, reads
// again at submission and finishes in the background; when the owners arrive
// they join the application's key people with their invite links. Two
// add-only fields say the answer is still on its way:
//
// - `ownershipPending` on the business block of `POST /business/select`: the
//   key-people prefill from that answer has no owners yet.
// - `keyPeopleOwnershipPending` on the completed-session summary: owners may
//   still be added to the list, so the success screen keeps re-reading.
//
// A missing field (an older server) means false.

/// Whether the register check at selection is still waiting on the owners.
bool selectOwnershipPending(Object? business) =>
    business is Map && business['ownershipPending'] == true;

/// Whether the submitted application may still gain owners from the register.
bool summaryOwnershipPending(Map<String, dynamic> json) =>
    json['keyPeopleOwnershipPending'] == true;

/// Whether the success screen should keep re-reading the summary: while
/// anybody still owes a check, and while owners from the register are still
/// on their way (they arrive with invite links that belong on this screen).
bool keepReadingSummary(List<AwaitingPerson> people, bool ownershipPending) =>
    ownershipPending || people.any((p) => p.stillOwes);

/// Which section of the key-people step carries the "still getting the
/// shareholders" note: Shareholders when the workflow shows it, else
/// Beneficial owners, else none (a workflow that collects no owners has
/// nothing to add).
KeyPeopleSection? ownershipNoteSection(List<KeyPeopleSection> sections) {
  if (sections.contains(KeyPeopleSection.shareholders)) {
    return KeyPeopleSection.shareholders;
  }
  if (sections.contains(KeyPeopleSection.ubos)) return KeyPeopleSection.ubos;
  return null;
}

/// The note on the key-people step.
const String kOwnershipPendingStepNote =
    'We are still getting the shareholders from the register. You can add them now, or they will be added when they arrive.';

/// The line under the key-people list on the success screen.
const String kOwnershipPendingSubmittedNote =
    'Shareholders from the register are still on their way. Their invite links will appear here when they arrive.';
