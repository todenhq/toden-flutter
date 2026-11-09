// Search by company name: the request it sends and the refusals that move the
// applicant to registration-number entry.
//
// Some registers charge per search (read through Didit), so the server needs
// the attempt session a search belongs to: one charge is scoped to and capped
// by it. A workflow can also switch search by name off (`business.nameSearch:
// false`). Mirrors the web SDK's `lib/business-search.ts` and the RN SDK's
// `config/businessSearch.ts`; keep the three in lockstep.

import '../services/api_service.dart' show VerificationApiException;
import 'business.dart' show WorkflowBusinessConfig;

/// Refusals after which search by name is not coming back for this attempt,
/// so the applicant is moved to registration-number entry. Never shown as "no
/// matches", which reads as "not registered". `search_unavailable` and
/// `search_rate_limited` are deliberately NOT here: they can be retried.
const List<String> kBusinessSearchRefusals = [
  'business_search_disabled',
  'session_required',
  'session_not_found',
  'insufficient_credits',
  'search_limit_reached',
  'pricing_not_configured',
];

/// What the details step says when search was refused and the server sent no
/// message.
const String kSearchRefusedFallback =
    'Search by name is not available for this verification. '
    'Enter the registration number.';

/// Whether the workflow offers search by name (absent = on).
bool nameSearchOffered(WorkflowBusinessConfig? business) =>
    business?.nameSearch != false;

/// The query parameters of `GET /business/search`.
Map<String, dynamic> businessSearchQueryParameters({
  required String country,
  required String query,
  String? subdivisionCode,
  int? limit,
  String? sessionId,
}) =>
    {
      'country': country,
      'query': query,
      if (subdivisionCode != null && subdivisionCode.isNotEmpty)
        'subdivisionCode': subdivisionCode,
      if (limit != null) 'limit': limit,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    };

/// A refusal the error carries, or null when it is not one (an outage or a
/// throttle, which keep the search on screen).
class BusinessSearchRefusal {
  final String code;

  /// The server's own message, or null when it sent none.
  final String? message;

  const BusinessSearchRefusal(this.code, this.message);
}

BusinessSearchRefusal? businessSearchRefusal(Object error) {
  if (error is! VerificationApiException) return null;
  if (!kBusinessSearchRefusals.contains(error.error)) return null;
  final message = error.message?.trim();
  return BusinessSearchRefusal(
    error.error,
    message == null || message.isEmpty ? null : message,
  );
}

/// What the FIRST screen of the business step shows. It always asks WHICH
/// company and nothing more; Continue checks the register and opens the second
/// screen filled in from its answer. With no search by name the question is
/// the registration number itself, never a jump to the full form. Mirrors the
/// web and RN `businessPickView` (lockstep).
({bool numberEntry, bool search, bool card}) businessPickView({
  required bool searchOffered,
  required bool refused,
  required bool manualEntry,
  required bool picked,
}) {
  final numberEntry = !searchOffered || refused || manualEntry;
  return (
    numberEntry: numberEntry,
    search: !numberEntry && !picked,
    card: !numberEntry && picked,
  );
}

// Test companies from the sandbox search are listed as "<searched> Sandbox
// <outcome> Ltd" so the outcomes can be told apart. Picked, a company carries
// the name that was searched ("Transika Ltd"), so its own documents name the
// same company the register does. MIRRORS kyc-core's withoutSandboxLabel
// (business-search/sandbox.ts) and the other two SDKs: keep the labels in step.
const List<String> _sandboxOutcomeLabels = [
  'Missing',
  'No Status',
  'Inactive',
  'Shareholders',
  'Late Shareholders',
  'Shareholders Unavailable',
  'No Shareholders',
  'No Key People',
];
final RegExp _sandboxLabelled = RegExp(
  '^(.+?)\\s+Sandbox(?:\\s+(?:${_sandboxOutcomeLabels.join('|')}))?\\s+Ltd\$',
  caseSensitive: false,
);

/// The name to keep for a picked search result.
String pickedBusinessName(String name) {
  final m = _sandboxLabelled.firstMatch(name.trim());
  return m == null ? name : '${m.group(1)} Ltd';
}
