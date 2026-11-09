// Workflow SCOPE — what a flow verifies about the subject (mirror of the
// server's lib/workflows/scope.ts and the web/RN SDKs' lib/scope.ts; keep the
// four in lockstep). Absent/null = the full verification.

const Set<String> kWorkflowScopes = {
  'address',
  'biometric-authentication',
  'biometric-enrollment',
  'questionnaire',
  'contact',
};

/// The marker idType a scoped submission carries (the KYB product-in-idType
/// convention; the server requires the matching published workflow).
const Map<String, String> kScopeIdTypes = {
  'address': 'address',
  'biometric-authentication': 'biometric-auth',
  'biometric-enrollment': 'biometric-enroll',
  'questionnaire': 'questionnaire',
  'contact': 'contact',
};

String? configScope(String? scope) =>
    scope != null && kWorkflowScopes.contains(scope) ? scope : null;

/// The biometric scopes run the liveness capture; every other scope has no
/// camera step at all.
bool isFaceScope(String? scope) =>
    scope == 'biometric-authentication' || scope == 'biometric-enrollment';

/// Scopes a BUSINESS workflow may carry: the address of its premises, a
/// questionnaire about the company, or its contact details. The biometric
/// scopes take a person's face and never apply to a business (the server
/// refuses them at publish). Mirrors the web SDK's lib/scope.ts.
const Set<String> kBusinessScopes = {'address', 'questionnaire', 'contact'};

/// Whether the workflow verifies something about a business (wording only).
bool isBusinessSubject(String? subjectType) => subjectType == 'business';

/// The KYB application flow (company search, registry lookup, key people,
/// documents): a business workflow with NO scope. A scoped business workflow
/// runs its scope's own steps instead.
bool isBusinessApplication(String? subjectType, String? scope) =>
    isBusinessSubject(subjectType) && configScope(scope) == null;

/// A scoped business workflow: the scope's own steps, worded for a business.
bool isScopedBusiness(String? subjectType, String? scope) {
  final s = configScope(scope);
  return isBusinessSubject(subjectType) && s != null && kBusinessScopes.contains(s);
}

/// A configuration the SDK refuses to run: a business workflow carrying a
/// biometric scope. It should never arrive (publish refuses it); if it does,
/// the flow shows the configuration error and never opens a camera.
bool unsupportedScopeConfig(String? subjectType, String? scope) {
  final s = configScope(scope);
  return isBusinessSubject(subjectType) && s != null && !kBusinessScopes.contains(s);
}

/// What the configuration-error screen says for [unsupportedScopeConfig].
const String kUnsupportedScopeMessage =
    'This verification is set up as a face check for a business, which is not '
    'supported. Contact the organisation that sent it.';
