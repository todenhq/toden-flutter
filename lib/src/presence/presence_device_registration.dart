import 'package:flutter/services.dart';

import '../utils/resolve_url.dart';
import 'presence_watch_status.dart';
import 'user_token.dart';

// ─── The presence device, from Dart (user token design rev 4, section 6b) ────
//
// Right after an address verification answers 202 with its HMAC
// presenceToken, the native side makes a key the OS never exports and
// registers it, with a presence user token Dart fetches from the host's
// provider. From then on native background code refreshes its own 1-hour
// token and seals each day (PresenceDevice.kt, PresenceDeviceClient.swift).
//
// With no provider nothing happens: the request needs a user token, and a
// host with none sends exactly what 4.4.0 sent. Never throws.

typedef PresenceChannelInvoke = Future<Object?> Function(String method, Map<String, Object?> args);

const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/presence');

Future<Object?> _invoke(String method, Map<String, Object?> args) => _channel.invokeMethod<Object?>(method, args);

final Map<String, Future<String>> _inflight = {};

/// Registers this phone's presence device for [externalUserId], if it has
/// none. Answers the native outcome (`registered`, `refused`, `limit`,
/// `delete_key`, `keep`, `no_key`, `user_token_invalid`), or `no_provider`,
/// `no_token` or `unavailable` from this side.
///
/// The 202 and a later enable can ask moments apart: one registration runs
/// per user at a time, and a second caller gets the first one's answer, so
/// two keys and two mints never race for the same device slot.
Future<String> registerPresenceDevice({
  required String apiKey,
  required String externalUserId,
  required String presenceToken,
  String? devUrl,
  TodenUserTokenProvider? getUserToken,
  PresenceChannelInvoke? invoke,
}) {
  final running = _inflight[externalUserId];
  if (running != null) return running;
  final run = _register(
    apiKey: apiKey,
    externalUserId: externalUserId,
    presenceToken: presenceToken,
    devUrl: devUrl,
    getUserToken: getUserToken,
    invoke: invoke,
  ).whenComplete(() {
    // A block, not an arrow: the removed value is this future, and returning
    // it would make whenComplete wait on itself.
    _inflight.remove(externalUserId);
  });
  _inflight[externalUserId] = run;
  return run;
}

Future<String> _register({
  required String apiKey,
  required String externalUserId,
  required String presenceToken,
  String? devUrl,
  TodenUserTokenProvider? getUserToken,
  PresenceChannelInvoke? invoke,
}) async {
  if ((getUserToken ?? TodenUserTokens.provider) == null) return 'no_provider';
  final call = invoke ?? _invoke;
  try {
    final base = <String, Object?>{
      'baseUrl': resolveBaseUrl(apiKey, devUrl: devUrl),
      'apiKey': apiKey,
      'externalUserId': externalUserId,
      'presenceToken': presenceToken,
    };
    // First with no token: a phone already registered (or refused for this
    // verification) answers at once, and the host's backend mints nothing.
    final first = (await call('registerPresenceDevice', base))?.toString() ?? 'keep';
    if (first != 'needs_token') return first;
    var outcome = 'user_token_invalid';
    // A token that registered another device, or was refreshed, is refused
    // with user_token_invalid: one fresh token and one more try.
    for (var attempt = 0; attempt < 2 && outcome == 'user_token_invalid'; attempt++) {
      final got = await TodenUserTokens.tokenFor(
        apiKey: apiKey,
        externalUserId: externalUserId,
        purpose: UserTokenPurpose.presence,
        getUserToken: getUserToken,
        force: true,
      );
      if (got.token == null) return 'no_token';
      outcome = (await call('registerPresenceDevice', {...base, 'userToken': got.token}))?.toString() ?? 'keep';
    }
    return outcome;
  } catch (_) {
    // MissingPluginException included: no native side, no device.
    return 'unavailable';
  }
}

/// The deadline day the native flush holds later days back for: the watch is
/// still in progress past its deadline (held for late sealed reports). Null
/// otherwise, which lets every sent day leave the queue.
String? heldDeadlineDay(PresenceWatchStatus status, DateTime now) {
  final deadline = status.deadlineAt;
  if (status.state != PresenceWatchState.inProgress || deadline == null || !now.isAfter(deadline)) return null;
  return deadline.toUtc().toIso8601String().substring(0, 10);
}

/// Hands the native flush the held deadline from a fresh status read.
Future<void> syncHeldDeadline(PresenceWatchStatus status, {DateTime? now, PresenceChannelInvoke? invoke}) async {
  try {
    await (invoke ?? _invoke)('setPresenceHeldDeadline', {'day': heldDeadlineDay(status, now ?? DateTime.now())});
  } catch (_) {
    // No native side: nothing is queued there.
  }
}

/// Logout: the device key, its registration and its marks go.
Future<void> forgetPresenceDevice(String externalUserId, {PresenceChannelInvoke? invoke}) async {
  try {
    await (invoke ?? _invoke)('forgetPresenceDevice', {'externalUserId': externalUserId});
  } catch (_) {
    // Best-effort by contract.
  }
}
