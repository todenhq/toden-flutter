import 'scope.dart';
import 'verification_config.dart';

/// Whether the liveness recording carries sound. Off unless a workflow asked.
/// Mirrored by the web (lib/liveness-audio.ts) and React Native
/// (config/livenessAudio.ts) SDKs: keep the three in lockstep.
bool recordsLivenessAudio(VerificationConfig config) {
  if (!config.livenessAudio) return false;
  // A scoped flow's own switches are its scope: only the two that capture a
  // face have a recording to put sound on.
  final scope = configScope(config.scope);
  if (scope != null) return isFaceScope(scope);
  return !isBusinessSubject(config.subjectType) &&
      config.enableSelfie &&
      config.enableLiveness;
}
