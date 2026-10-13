import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/verification_config.dart';
import '../providers/camera_provider.dart';
import '../providers/verification_provider.dart';
import '../providers/verification_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/theme_provider.dart';

// ─── The scope a flow mounts in ──────────────────────────────────────────────
//
// One override list, shared by every host that runs a step of the flow: the KYC
// flow itself and face re-authentication, which hosts the liveness step in its
// own scope.
//
// It lives in its OWN file rather than beside Verification because both hosts need
// it and the entry point needs to be able to mount either: with the list on
// Verification, the biometric host imported the KYC widget, so the KYC widget could
// not import the biometric host back without an import cycle (2026-09-16).

/// The theme mode a flow opens in, from the consumer's appearance.
ThemeMode initialThemeMode(VerificationAppearance? a) => switch (a?.theme) {
      VerificationThemeMode.light => ThemeMode.light,
      VerificationThemeMode.dark => ThemeMode.dark,
      VerificationThemeMode.system || null => ThemeMode.system,
    };

/// The ProviderScope overrides a flow mounts with, optionally carrying the
/// server config a workflow resolution already fetched. One list, so a notifier
/// added here reaches every host.
List<Override> verificationFlowOverrides(
  VerificationConfig config,
  ServerSdkConfig? preloaded,
) =>
    [
      // Config must be first — the notifiers read it during build.
      verificationConfigProvider.overrideWithValue(config),
      if (preloaded != null)
        preloadedServerConfigProvider.overrideWithValue(preloaded),
      // Scope all three KYC notifiers to this container so they read
      // verificationConfigProvider from the override above, not from the root
      // ProviderScope (which has no override and would throw).
      kYCNotifierProvider.overrideWith(VerificationNotifier.new),
      cameraNotifierProvider.overrideWith(CameraNotifier.new),
      livenessNotifierProvider.overrideWith(LivenessNotifier.new),
      verificationThemeModeProvider.overrideWith((ref) => initialThemeMode(config.appearance)),
      // Per flow, so one flow's selfie camera never lights another's screen.
      livenessCameraOnProvider.overrideWith((ref) => false),
    ];
