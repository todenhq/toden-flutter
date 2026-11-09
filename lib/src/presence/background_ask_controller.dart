import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../config/verification_config.dart';
import 'background_presence.dart';
import 'presence_auto_report.dart';
import 'presence_background_primer.dart';
import 'presence_status.dart';
import 'presence_store.dart';

/// The "allow all the time" answer, for the success card: [on], [off] (they
/// said no or not now), or null when nothing was asked.
enum BackgroundOutcome { on, off }

/// The submitted screen's side of the "allow all the time" ask
/// (presence_background_primer.dart). After a successful submission [begin]
/// decides: show the explanation screen first, or go straight to the success
/// screen, having armed silently when the permission is already granted. From
/// [BackgroundOutcome.off] the card can open Settings; coming back with the
/// permission granted arms it and flips the card, with no second prompt.
/// Mirrors the React Native SDK's presence/use-background-ask.ts.
class BackgroundAskController extends ChangeNotifier with WidgetsBindingObserver {
  BackgroundAskController(this.config) {
    WidgetsBinding.instance.addObserver(this);
  }

  final VerificationConfig config;
  BackgroundOutcome? _outcome;
  bool _awaitingSettings = false;
  bool _foregroundGranted = true;
  bool _settingsOffer = false;
  Timer? _permissionWatch;
  int? _androidApi;

  BackgroundOutcome? get outcome => _outcome;

  /// Location is already allowed while using the app. Read before the screen
  /// shows, so what it says the phone will ask is right on its first frame.
  bool get foregroundGranted => _foregroundGranted;

  /// The phone's answer could not be seen: the screen stays, offers Settings,
  /// and watches the permission itself.
  bool get settingsOffer => _settingsOffer;

  /// The Android API level; null on iOS, or when it could not be read.
  int? get androidApi => _androidApi;

  void _set(BackgroundOutcome value) {
    _outcome = value;
    notifyListeners();
  }

  static Future<bool> _alwaysGranted() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// After the submission: true shows the explanation screen.
  Future<bool> begin({required bool resumed}) async {
    final wants = wantsBackgroundPresence(config);
    final decision = backgroundPrimerDecision(
      wantsBackground: wants,
      // The plugin's native side receives fence events with no app root setup.
      registered: wants,
      alwaysGranted: wants && await _alwaysGranted(),
      resumed: resumed,
    );
    if (decision == PrimerDecision.primer) {
      await _readPermissionState();
      unawaited(autoReportPresence(config, askForBackground: false));
      return true;
    }
    // Silent arms with no prompt; skip makes no background ask at all.
    unawaited(autoReportPresence(config));
    if (decision == PrimerDecision.silent) _set(BackgroundOutcome.on);
    return false;
  }

  Future<void> _readPermissionState() async {
    try {
      final permission = await Geolocator.checkPermission();
      _foregroundGranted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      _foregroundGranted = true;
    }
    if (!Platform.isAndroid) return;
    try {
      _androidApi = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      _androidApi = null;
    }
  }

  Future<EnableBackgroundResult?> _enable() async {
    try {
      return await BackgroundPresence.enable(
        apiKey: config.apiKey,
        externalUserId: config.userId!,
        devUrl: config.devUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// The person tapped allow: the OS prompt, then the answer.
  Future<AllowNext> allow() async {
    await markBackgroundAsked(config.userId!);
    final next = afterAllow(await _enable());
    switch (next) {
      case AllowNext.offer:
        _settingsOffer = true;
        _watchPermission();
        notifyListeners();
      case AllowNext.on:
        _set(BackgroundOutcome.on);
      case AllowNext.off:
        _set(BackgroundOutcome.off);
    }
    return next;
  }

  void later() {
    _stopWatching();
    _set(BackgroundOutcome.off);
  }

  void _stopWatching() {
    _settingsOffer = false;
    _permissionWatch?.cancel();
    _permissionWatch = null;
  }

  /// The one reliable sign: the permission itself. It covers a prompt answered
  /// late and a trip to Settings alike, whatever the app's state did meanwhile.
  void _watchPermission() {
    var checking = false;
    _permissionWatch = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (checking) return;
      checking = true;
      if (await _alwaysGranted()) {
        _permissionWatch?.cancel();
        // Already granted, so this arms the fence with no prompt.
        final result = await _enable();
        _stopWatching();
        _set(result?.started == true ? BackgroundOutcome.on : BackgroundOutcome.off);
      }
      checking = false;
    });
  }

  /// From the success card: the app's settings, where "all the time" lives.
  void openSettings() {
    _awaitingSettings = true;
    unawaited(openLocationSettings());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingSettings) return;
    _awaitingSettings = false;
    unawaited(() async {
      if (!await _alwaysGranted()) return;
      // Already granted, so this arms the fence with no prompt.
      final result = await _enable();
      if (result?.started == true) _set(BackgroundOutcome.on);
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionWatch?.cancel();
    super.dispose();
  }
}
