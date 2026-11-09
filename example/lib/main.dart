import 'package:flutter/material.dart';
import 'package:toden_flutter/toden_flutter.dart';

// Credentials come from --dart-define so no real key is ever committed here.
// Against a local kyc-core, pass all three:
//
//   flutter run \
//     --dart-define=TODEN_API_KEY=pk_dev_... \
//     --dart-define=TODEN_DEV_SERVER=http://$(ipconfig getifaddr en0):3001 \
//     --dart-define=TODEN_WORKFLOW_ID=wf_...
//
// The key prefix picks the environment, so TODEN_DEV_SERVER is read only by a
// `pk_dev_*` key. A `pk_test_*` key targets staging and ignores it, which is
// why the placeholder default below cannot reach a machine on your desk.
const String kApiKey = String.fromEnvironment(
  'TODEN_API_KEY',
  defaultValue: 'pk_test_xxxxxxxxxxxxxxxxxxxxxxxx',
);
const String kDevServer = String.fromEnvironment('TODEN_DEV_SERVER');
const String kWorkflowId = String.fromEnvironment('TODEN_WORKFLOW_ID');
// The org's user reference. Address presence reports only for a named user.
const String kUserId = String.fromEnvironment('TODEN_USER_ID', defaultValue: 'usr_123');
// The person's email, passed as userData. Optional: it also lets the flow
// offer an address they saved before without an email step.
const String kUserEmail = String.fromEnvironment('TODEN_USER_EMAIL');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Toden Identity Example',
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _startVerification(BuildContext context) {
    // On-device liveness ships inside the SDK and is on by default — no setup
    // needed. The flow uploads media and submits, then returns immediately;
    // the verification result is delivered asynchronously via webhook.
    Verification.show(
      context: context,
      config: VerificationConfig(
        // The environment is derived from the key prefix — a `pk_test_*` key
        // targets staging automatically (no `environment` parameter).
        apiKey: kApiKey,
        devUrl: kDevServer.isEmpty ? null : kDevServer,
        workflowId: kWorkflowId.isEmpty ? null : kWorkflowId,
        userId: kUserId,
        userData: kUserEmail.isEmpty ? null : const UserData(email: kUserEmail),
        // A workflow declares its own countries and ID types, so these are
        // omitted when one is set. Passing them anyway narrows a multi-region
        // flow to this hardcoded list: such a flow keeps its ID types per
        // country and leaves the top-level list unset, and the merge treats
        // "unset" as "the flow did not define it" and keeps the prop.
        country: kWorkflowId.isEmpty ? 'NG' : null,
        idTypes: kWorkflowId.isEmpty ? const ['bvn', 'nin', 'passport'] : null,
        enableSelfie: true,
        enableDocumentCapture: true,
        enableLiveness: true,
        appearance: const VerificationAppearance(
          companyName: 'Toden',
          theme: VerificationThemeMode.light,
        ),
        metadata: const {'userId': kUserId},
      ),
      onSubmit: (VerificationSubmission submission) {
        // Fires once the server accepts the submission. `status` is always
        // 'pending' here — the final outcome arrives later via webhook (or by
        // polling GET /api/v1/status/:verificationId).
        debugPrint('Submitted: ${submission.verificationId}');
      },
      onError: (VerificationError error) {
        // Technical errors only (network / invalid key / insufficient credits /
        // upload). Verification *failures* never come through here.
        debugPrint('Error (${error.code}): ${error.message}');
      },
      onClose: () => debugPrint('KYC closed'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Toden Example')),
      body: Center(
        child: FilledButton(
          onPressed: () => _startVerification(context),
          child: const Text('Verify Identity'),
        ),
      ),
    );
  }
}
