import '../config/scope.dart';
import '../presence/user_token.dart';
import 'api_service.dart';

// ─── Embedded face checks with a scoped publishable key (design rev 4, §6a) ──
//
// A scoped key may mount the biometric-authentication or biometric-enrollment
// scope only with a biometric user token for the same user, minted by the
// host's backend. Each mount spends one use, so the SDK fetches a fresh token
// per flow start, keeps it in memory for that flow only and never persists it.
//
// The SDK cannot tell a scoped key from a legacy one, so: with a provider,
// fetch and send (a legacy key ignores the header); with no provider, every
// request is byte-identical to 4.4.0.
//
//   - A face-scope config: a token before /session/start.
//   - A workflow mount (the scope is the server's to know): on 403
//     `user_token_required` with a provider, one fetch and one retry. The one
//     exception to "never retry user_token_required" (section 14).
//   - /verify answering 403 `user_token_invalid`: a fresh token, /session/start
//     again (a resume, which rebinds), and one resubmission. 429
//     `too_many_attempts` goes to the host, never retried.
// Mirrors the RN SDK's services/mount-user-token.ts.

/// The user-token refusal an API error carries, from its code only.
UserTokenErrorCode? mountRefusalOf(Object error) =>
    error is VerificationApiException ? userTokenRefusal({'error': error.error}) : null;

bool _hasProvider(TodenUserTokenProvider? getUserToken) => (getUserToken ?? TodenUserTokens.provider) != null;

/// The headers a mount sends: a fresh biometric token when one is due, else
/// none. Throws [UserTokenException] (`userTokenMismatch`) when the provider's
/// answer is for someone else: nothing is sent then.
Future<Map<String, String>> mountTokenHeaders({
  required String apiKey,
  required String? externalUserId,
  required String? scope,
  TodenUserTokenProvider? getUserToken,
  bool anyScope = false,
}) async {
  if (externalUserId == null || externalUserId.isEmpty || !_hasProvider(getUserToken)) return const {};
  if (!anyScope && !isFaceScope(scope)) return const {};
  final got = await TodenUserTokens.tokenFor(
    apiKey: apiKey,
    externalUserId: externalUserId,
    purpose: UserTokenPurpose.biometric,
    getUserToken: getUserToken,
    force: true,
  );
  if (got.mismatch) throw const UserTokenException(UserTokenErrorCode.userTokenMismatch);
  return userTokenHeaders(got.token);
}

/// One /session/start with the mount's token. A workflow mount the server
/// says needs one gets one fetch and one retry, with a provider.
Future<T> startWithMountToken<T>({
  required String apiKey,
  required String? externalUserId,
  required String? scope,
  TodenUserTokenProvider? getUserToken,
  required Future<T> Function(Map<String, String> headers) start,
  // A re-mount after /verify's user_token_invalid: the server has said this
  // session needs a token, whatever the config's scope.
  bool anyScope = false,
}) async {
  final headers = await mountTokenHeaders(
      apiKey: apiKey, externalUserId: externalUserId, scope: scope, getUserToken: getUserToken, anyScope: anyScope);
  try {
    return await start(headers);
  } catch (e) {
    final refusal = mountRefusalOf(e);
    if (refusal == UserTokenErrorCode.userTokenRequired &&
        !headers.containsKey(kUserTokenHeader) &&
        _hasProvider(getUserToken)) {
      final retry = await mountTokenHeaders(
          apiKey: apiKey, externalUserId: externalUserId, scope: scope, getUserToken: getUserToken, anyScope: true);
      if (retry.containsKey(kUserTokenHeader)) return start(retry);
    }
    if (refusal != null) TodenUserTokens.warnOnce(refusal);
    rethrow;
  }
}

/// Whether a /verify failure is one a re-mount with a fresh token can fix.
bool remountFixes(Object error, {required String? externalUserId, TodenUserTokenProvider? getUserToken}) =>
    mountRefusalOf(error) == UserTokenErrorCode.userTokenInvalid &&
    externalUserId != null &&
    externalUserId.isNotEmpty &&
    _hasProvider(getUserToken);
