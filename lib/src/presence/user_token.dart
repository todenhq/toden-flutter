import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─── User tokens for scoped publishable keys (Toden design 0020, §14) ────────
//
// A scoped publishable key cannot read or write one user's presence on its
// own: the server wants a short-lived user token, minted by the customer's
// backend with a secret key, in the X-Toden-User-Token header. The SDK never
// mints one. The host gives it a provider, which asks the host's own backend;
// the provider gets NO user id, because the backend knows who is signed in.
//
//   - No provider: no header, and every request is byte-identical to 4.4.0.
//   - A provider's answer is checked before it is used: the user, the purpose,
//     the token's shape and environment, and its expiry. Anything else is
//     discarded, nothing is sent, and the call ends `userTokenMismatch`.
//   - A provider that fails or answers null means "no token": the request goes
//     without the header, which a legacy key does not need.
//   - 403 `user_token_invalid` with a provider: one new token, one retry.
//     Nothing else is retried, `user_token_required` included. The CODE decides.
//   - Tokens are never logged. A presence token is handed to the native store
//     (Keychain / noBackupFilesDir) only after the identity check; a biometric
//     token is never kept.
// Mirrors the RN SDK's presence/user-token.ts; the shared cases are in
// test/user_token_vectors.json.

const String kUserTokenHeader = 'X-Toden-User-Token';

enum UserTokenPurpose { presence, biometric }

/// What the customer's backend got back from `POST /user-tokens/{purpose}`
/// (the JSON body as a map), or null when there is no token.
typedef TodenUserTokenProvider = Future<Map<String, dynamic>?> Function(UserTokenPurpose purpose);

/// The server's user-token refusals, and the SDK's own `user_token_mismatch`.
enum UserTokenErrorCode {
  userTokenRequired,
  userTokenInvalid,
  scopeNotDeclared,
  userTokenMismatch,
}

const Map<String, UserTokenErrorCode> _refusalCodes = {
  'user_token_required': UserTokenErrorCode.userTokenRequired,
  'user_token_invalid': UserTokenErrorCode.userTokenInvalid,
  'scope_not_declared': UserTokenErrorCode.scopeNotDeclared,
};

String userTokenErrorWire(UserTokenErrorCode code) => switch (code) {
      UserTokenErrorCode.userTokenRequired => 'user_token_required',
      UserTokenErrorCode.userTokenInvalid => 'user_token_invalid',
      UserTokenErrorCode.scopeNotDeclared => 'scope_not_declared',
      UserTokenErrorCode.userTokenMismatch => 'user_token_mismatch',
    };

const Map<UserTokenErrorCode, String> _messages = {
  UserTokenErrorCode.userTokenRequired:
      'This request needs a user token from your server. Pass getUserToken to the SDK.',
  UserTokenErrorCode.userTokenInvalid: 'The user token was not accepted. Your server should issue a new one.',
  UserTokenErrorCode.scopeNotDeclared: 'A publishable key limited to workflows cannot use address presence.',
  UserTokenErrorCode.userTokenMismatch:
      'The user token from your server is for another user or purpose, or has expired.',
};

class UserTokenException implements Exception {
  final UserTokenErrorCode code;
  const UserTokenException(this.code);
  @override
  String toString() => 'UserTokenException(${userTokenErrorWire(code)}): ${_messages[code]}';
}

class CheckedUserToken {
  final String token;
  final String externalUserId;
  final UserTokenPurpose purpose;
  final int expiresAtMillis;
  const CheckedUserToken(
    this.token,
    this.externalUserId,
    this.purpose,
    this.expiresAtMillis,
  );
}

final RegExp _tokenShape = RegExp(r'^ut_(live|test|dev)_[A-Za-z0-9_-]{43}$');
final RegExp _keyEnv = RegExp(r'^(?:pk|sk)_(live|test|dev)_');

/// PURE. The provider's answer as a token the SDK may send for this user and
/// purpose, or null when it must be discarded.
CheckedUserToken? checkUserToken(
  Object? body, {
  required String externalUserId,
  required UserTokenPurpose purpose,
  required String apiKey,
  required int nowMillis,
}) {
  if (body is! Map) return null;
  final token = body['token'];
  final user = body['externalUserId'];
  final p = body['purpose'];
  final expiresAt = body['expiresAt'];
  if (token is! String || user is! String || p is! String || expiresAt is! String) return null;
  if (user != externalUserId || p != purpose.name) return null;
  final shape = _tokenShape.firstMatch(token);
  final env = _keyEnv.firstMatch(apiKey);
  if (shape == null || env == null || shape.group(1) != env.group(1)) return null;
  final expires = DateTime.tryParse(expiresAt)?.millisecondsSinceEpoch;
  if (expires == null || expires <= nowMillis) return null;
  return CheckedUserToken(token, user, purpose, expires);
}

/// PURE. The user-token refusal an error answer carries, from its code only.
UserTokenErrorCode? userTokenRefusal(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  final code = error is Map ? error['code'] : (error is String ? error : body['code']);
  return code is String ? _refusalCodes[code] : null;
}

/// The header for a token, or nothing, so a request without one is unchanged.
Map<String, String> userTokenHeaders(String? token) =>
    token == null || token.isEmpty ? const {} : {kUserTokenHeader: token};

class _Cached {
  final CheckedUserToken checked;
  final int fetchedAtMillis;
  bool stale = false;
  _Cached(this.checked, this.fetchedAtMillis);

  /// Past half its life, a token is renewed before it is used.
  bool usable(int now) => !stale && now < fetchedAtMillis + (checked.expiresAtMillis - fetchedAtMillis) ~/ 2;
}

class TokenLookup {
  final String? token;
  final bool mismatch;
  const TokenLookup(this.token, {this.mismatch = false});
}

/// The provider, the token cache and the hand-over to the native store.
class TodenUserTokens {
  TodenUserTokens._();

  static TodenUserTokenProvider? _provider;
  static final Map<String, _Cached> _cache = {};
  static final Set<UserTokenErrorCode> _warned = {};

  static const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/presence');

  /// Every presence token accepted here goes to the native background store
  /// (Keychain on iOS, noBackupFilesDir on Android), which flushes the queue
  /// it held. Tests replace it.
  static Future<void> Function(CheckedUserToken token)? onAccepted = _toNative;

  static Future<void> _toNative(CheckedUserToken t) async {
    await _channel.invokeMethod<void>('setPresenceUserToken', {
      'externalUserId': t.externalUserId,
      'token': t.token,
      'expiresAtMillis': t.expiresAtMillis,
    });
  }

  /// Logout or stand-down: the native store forgets the user's token.
  static Future<void> clearNative(String externalUserId) async {
    forget(externalUserId);
    try {
      await _channel.invokeMethod<void>('clearPresenceUserToken', {'externalUserId': externalUserId});
    } catch (_) {
      // No native side: nothing was kept.
    }
  }

  static String? _lastApiKey;
  static String? _lastUser;

  /// Hand the SDK a presence token the host already has, most often from a
  /// silent push, so the background queue can go without the app being
  /// opened. [body] is the mint response. Checked exactly as a provider's
  /// answer is, against [externalUserId] and [apiKey]. Without them, the user
  /// and key the last presence call used in this process, else (a cold start
  /// from a push) the user and key background presence is armed for, read
  /// from the native store, as the React Native SDK reads its own.
  /// Throws [UserTokenException] (`userTokenMismatch`).
  static Future<void> setUserToken(
    Map<String, dynamic> body, {
    String? apiKey,
    String? externalUserId,
  }) async {
    var user = externalUserId ?? _lastUser;
    var key = apiKey ?? _lastApiKey;
    if (user == null || key == null) {
      final armed = await armedReporter();
      if (armed != null && (user == null || user == armed.externalUserId)) {
        user ??= armed.externalUserId;
        key ??= armed.apiKey;
      }
    }
    await accept(body, externalUserId: user, apiKey: key);
  }

  /// The user and key background presence is armed for, or null. Tests replace it.
  static Future<({String externalUserId, String apiKey})?> Function() armedReporter = _armedReporter;

  static Future<({String externalUserId, String apiKey})?> _armedReporter() async {
    try {
      final armed = await _channel.invokeMethod<Map<Object?, Object?>>('presenceArmedReporter');
      final user = armed?['externalUserId'];
      final key = armed?['apiKey'];
      return user is String && key is String ? (externalUserId: user, apiKey: key) : null;
    } catch (_) {
      return null;
    }
  }

  /// The provider every presence call uses when it is not given its own.
  static void setProvider(TodenUserTokenProvider? provider) => _provider = provider;
  static TodenUserTokenProvider? get provider => _provider;

  @visibleForTesting
  static void reset() {
    _provider = null;
    _lastApiKey = null;
    _lastUser = null;
    onAccepted = _toNative;
    armedReporter = _armedReporter;
    _cache.clear();
    _warned.clear();
  }

  static String _key(String user, UserTokenPurpose purpose) => '${purpose.name}\u0000$user';

  static void warnOnce(UserTokenErrorCode code) {
    if (!_warned.add(code)) return;
    // Never the token: only the code and what to do about it.
    if (kDebugMode) debugPrint('[toden] ${userTokenErrorWire(code)}: ${_messages[code]}');
  }

  /// Forget a token the server refused. With [token], only that token: a
  /// newer one accepted while the refused request was out stays good.
  static void markStale(String externalUserId, UserTokenPurpose purpose, {String? token}) {
    final hit = _cache[_key(externalUserId, purpose)];
    if (hit != null && (token == null || hit.checked.token == token)) hit.stale = true;
  }

  static void forget(String externalUserId) {
    _cache.remove(_key(externalUserId, UserTokenPurpose.presence));
    _cache.remove(_key(externalUserId, UserTokenPurpose.biometric));
  }

  static Future<void> _accept(CheckedUserToken checked, int now) async {
    _cache[_key(checked.externalUserId, checked.purpose)] = _Cached(
      checked,
      now,
    );
    final keep = onAccepted;
    if (checked.purpose == UserTokenPurpose.presence && keep != null) {
      try {
        await keep(checked);
      } catch (_) {
        // Keeping it for the background is best-effort; the call still has it.
      }
    }
  }

  /// The token to send: cached, or fetched when missing, stale or past half
  /// its life.
  static Future<TokenLookup> tokenFor({
    required String apiKey,
    required String externalUserId,
    required UserTokenPurpose purpose,
    TodenUserTokenProvider? getUserToken,
    bool force = false,
    int Function()? now,
  }) async {
    _lastApiKey = apiKey;
    _lastUser = externalUserId;
    final provider = getUserToken ?? _provider;
    if (provider == null) return const TokenLookup(null);
    final clock = now ?? () => DateTime.now().millisecondsSinceEpoch;
    final hit = _cache[_key(externalUserId, purpose)];
    if (!force && hit != null && hit.usable(clock())) return TokenLookup(hit.checked.token);
    Map<String, dynamic>? body;
    try {
      body = await provider(purpose);
    } catch (_) {
      // A provider that fails (offline, its server down) is not the host
      // saying "no token": a token past half its life but still good is sent
      // rather than nothing, which a scoped key would refuse. Never after a
      // refusal.
      final stillGood = !force && hit != null && !hit.stale && clock() < hit.checked.expiresAtMillis;
      return TokenLookup(stillGood ? hit.checked.token : null);
    }
    if (body == null) return const TokenLookup(null);
    final checked = checkUserToken(
      body,
      externalUserId: externalUserId,
      purpose: purpose,
      apiKey: apiKey,
      nowMillis: clock(),
    );
    if (checked == null) {
      _cache.remove(_key(externalUserId, purpose));
      warnOnce(UserTokenErrorCode.userTokenMismatch);
      return const TokenLookup(null, mismatch: true);
    }
    await _accept(checked, clock());
    return TokenLookup(checked.token);
  }

  /// On app open, with a provider: make sure the native background store has
  /// a fresh token (the native side may have marked its copy stale), which
  /// also flushes the days it held. Never throws.
  static Future<void> refreshBackground({
    required String apiKey,
    required String externalUserId,
    TodenUserTokenProvider? getUserToken,
  }) async {
    if ((getUserToken ?? _provider) == null) return;
    final hit = _cache[_key(externalUserId, UserTokenPurpose.presence)];
    final cachedBefore = hit != null && hit.usable(DateTime.now().millisecondsSinceEpoch);
    final lookup = await tokenFor(
        apiKey: apiKey, externalUserId: externalUserId, purpose: UserTokenPurpose.presence, getUserToken: getUserToken);
    // A token fetched just now was already handed over by tokenFor.
    final keep = onAccepted;
    if (lookup.token == null || !cachedBefore || keep == null) return;
    try {
      await keep(hit.checked);
    } catch (_) {
      // Best-effort: the background waits for the next open.
    }
  }

  /// A token the host already has (a silent push): checked as a provider's
  /// answer is. Throws [UserTokenException] with `userTokenMismatch`.
  static Future<CheckedUserToken> accept(
    Map<String, dynamic> body, {
    required String? externalUserId,
    required String? apiKey,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final purpose = body['purpose'] == 'biometric' ? UserTokenPurpose.biometric : UserTokenPurpose.presence;
    final checked = externalUserId == null || apiKey == null
        ? null
        : checkUserToken(
            body,
            externalUserId: externalUserId,
            purpose: purpose,
            apiKey: apiKey,
            nowMillis: now,
          );
    if (checked == null) {
      warnOnce(UserTokenErrorCode.userTokenMismatch);
      throw const UserTokenException(UserTokenErrorCode.userTokenMismatch);
    }
    await _accept(checked, now);
    return checked;
  }
}

/// One request's outcome: the answer, or why a user token stopped it.
class UserTokenSend<T> {
  /// The last answer, 2xx or not. Null when nothing came back.
  final Response<T>? response;
  final UserTokenErrorCode? refusal;
  const UserTokenSend(this.response, this.refusal);
  bool get ok {
    final status = response?.statusCode;
    return refusal == null && status != null && status >= 200 && status < 300;
  }
}

Future<Response<T>?> _attempt<T>(
  Future<Response<T>> Function(Map<String, String>) send,
  String? token,
) async {
  try {
    return await send(userTokenHeaders(token));
  } on DioException catch (e) {
    final response = e.response;
    return response == null
        ? null
        : Response<T>(
            requestOptions: response.requestOptions,
            statusCode: response.statusCode,
            data: response.data is T ? response.data as T : null,
            extra: {'body': response.data},
          );
  }
}

UserTokenErrorCode? _refusalOf(Response<dynamic>? response) {
  if (response == null) return null;
  final status = response.statusCode ?? 0;
  if (status >= 200 && status < 300) return null;
  return userTokenRefusal(response.extra['body'] ?? response.data);
}

/// Send one request with the user's token, when there is one. A 403
/// `user_token_invalid`, with a provider, gets one new token and one retry;
/// nothing else is retried (design section 14: never `user_token_required`).
Future<UserTokenSend<T>> sendWithUserToken<T>({
  required String apiKey,
  required String externalUserId,
  required UserTokenPurpose purpose,
  TodenUserTokenProvider? getUserToken,
  required Future<Response<T>> Function(Map<String, String> headers) send,
}) async {
  final first = await TodenUserTokens.tokenFor(
    apiKey: apiKey,
    externalUserId: externalUserId,
    purpose: purpose,
    getUserToken: getUserToken,
  );
  if (first.mismatch) return const UserTokenSend(null, UserTokenErrorCode.userTokenMismatch);
  var response = await _attempt(send, first.token);
  var refusal = _refusalOf(response);
  final hasProvider = (getUserToken ?? TodenUserTokens.provider) != null;
  if (hasProvider && refusal == UserTokenErrorCode.userTokenInvalid) {
    TodenUserTokens.markStale(externalUserId, purpose, token: first.token);
    final next = await TodenUserTokens.tokenFor(
      apiKey: apiKey,
      externalUserId: externalUserId,
      purpose: purpose,
      getUserToken: getUserToken,
      force: true,
    );
    if (next.mismatch) return UserTokenSend(response, UserTokenErrorCode.userTokenMismatch);
    if (next.token != null) {
      response = await _attempt(send, next.token);
      refusal = _refusalOf(response);
    }
  }
  if (refusal != null) TodenUserTokens.warnOnce(refusal);
  return UserTokenSend(response, refusal);
}
