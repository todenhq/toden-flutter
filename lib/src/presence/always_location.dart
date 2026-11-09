import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

// Asking for "allow all the time", and knowing whether the OS really asked.

/// The permission after the escalation, and whether the OS showed a prompt
/// for its last step. Null permission when the platform could not answer.
typedef AlwaysAnswer = ({LocationPermission? permission, bool osPrompted});

/// The two-step escalation to "allow all the time": while-in-use first, then
/// a second request for the background permission. Shared by the geofence and
/// the foreground-service tiers so the two can never ask differently. Null
/// when the platform could not answer at all.
Future<LocationPermission?> requestAlwaysLocationPermission() async =>
    (await requestAlwaysLocation()).permission;

/// [requestAlwaysLocationPermission], saying whether a prompt appeared.
Future<AlwaysAnswer> requestAlwaysLocation() async {
  try {
    var permission = await Geolocator.checkPermission();
    // Already refused for good: no prompt can come, only Settings.
    if (permission == LocationPermission.deniedForever) {
      return (permission: permission, osPrompted: false);
    }
    if (permission == LocationPermission.denied) {
      final asked = await _timedRequest(Geolocator.requestPermission);
      permission = asked.$1;
      if (permission != LocationPermission.whileInUse) {
        return (permission: permission, osPrompted: asked.$2);
      }
    }
    if (permission == LocationPermission.whileInUse) {
      return await _requestAlwaysNatively(permission);
    }
    return (permission: permission, osPrompted: true);
  } catch (_) {
    return (permission: null, osPrompted: true);
  }
}

/// Android gives no signal for a prompt, but no person answers within half a
/// second, so an instant answer means the OS showed nothing.
Future<(T, bool)> _timedRequest<T>(Future<T> Function() request) async {
  final watch = Stopwatch()..start();
  final answer = await request();
  return (answer, osPromptedAfter(watch.elapsed, isIOS: Platform.isIOS));
}

/// Pure: iOS reports a missing prompt itself, so only Android reads the clock.
bool osPromptedAfter(Duration elapsed, {required bool isIOS}) =>
    isIOS || elapsed >= const Duration(milliseconds: 500);

/// The second step is asked by the plugin's own native code on both
/// platforms, because geolocator's second request never reaches the system
/// prompt on either:
///   • iOS: it returns at once when any decision already exists, and with
///     both usage strings declared it only ever asks for "While Using".
///   • Android 11+: it asks for background location together with the
///     foreground permissions, and the system ignores a mixed request.
/// iOS shows its prompt once per install and Android stops after two
/// refusals; after that this answers the current permission without one.
Future<AlwaysAnswer> _requestAlwaysNatively(LocationPermission current) async {
  if (!Platform.isIOS && !Platform.isAndroid) {
    return (permission: current, osPrompted: true);
  }
  try {
    final asked = await _timedRequest(
      () => const MethodChannel('kyc_sdk_flutter/presence')
          .invokeMethod<String>('requestAlwaysLocation'),
    );
    final word = asked.$1;
    final prompted = asked.$2 && word?.startsWith(noPromptPrefix) != true;
    return (
      permission: alwaysAnswerToPermission(word, current),
      osPrompted: prompted
    );
  } catch (_) {
    return (permission: current, osPrompted: true);
  }
}

/// iOS's mark on an answer it gave without showing a prompt.
const noPromptPrefix = 'noPrompt:';

/// Pure: the native side's answer as a geolocator permission. An answer this
/// build does not know keeps [current].
LocationPermission alwaysAnswerToPermission(
    String? word, LocationPermission current) {
  switch (word?.replaceFirst(noPromptPrefix, '')) {
    case 'always':
      return LocationPermission.always;
    case 'whileInUse':
      return LocationPermission.whileInUse;
    case 'denied':
      return LocationPermission.deniedForever;
    default:
      return current;
  }
}
