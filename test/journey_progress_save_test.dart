import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/utils/step_log.dart';

// Something that gets in the way is saved with the progress at once, not on
// the next step change: an applicant who refuses the camera or presses Close
// may never reach another step, and the journey would never leave the phone.

class _RecordingApi extends VerificationApiService {
  _RecordingApi() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final saved = <Map<String, dynamic>>[];

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {
    saved.add(progress);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, _RecordingApi)> open() async {
    final api = _RecordingApi();
    final c = ProviderContainer(overrides: [
      verificationConfigProvider.overrideWithValue(
        const VerificationConfig(apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', country: 'NG'),
      ),
      verificationApiServiceProvider.overrideWithValue(api),
      preloadedServerConfigProvider.overrideWithValue(const ServerSdkConfig(status: ServerConfigStatus.ready)),
      kYCNotifierProvider.overrideWith(VerificationNotifier.new),
    ]);
    c.read(kYCNotifierProvider);
    // Wait for the session itself, up to two seconds: a fixed number of
    // microtask turns was enough on a laptop and not on a slower CI runner.
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (c.read(kYCNotifierProvider).sessionId == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return (c, api);
  }

  test('a Close on the consent screen reaches the server at once, with the journey', () async {
    final (c, api) = await open();
    addTearDown(c.dispose);
    expect(c.read(kYCNotifierProvider).sessionId, 'hs_test');
    expect(api.saved, isEmpty);

    StepLog.recordEvent('flow_closed');

    expect(api.saved, hasLength(1));
    final log = api.saved.single['stepLog'] as Map<String, dynamic>;
    expect((log['events'] as List).single, containsPair('code', 'flow_closed'));
    expect((log['client'] as Map)['sdk'], 'flutter');
  });

  test('leaving the app on the consent screen is not a start', () async {
    final (c, api) = await open();
    addTearDown(c.dispose);
    StepLog.recordEvent('app_backgrounded');
    expect(api.saved, isEmpty);
  });

  test('a closed flow stops asking', () async {
    final (c, api) = await open();
    c.dispose();
    StepLog.recordEvent('flow_closed');
    expect(api.saved, isEmpty);
  });
}
