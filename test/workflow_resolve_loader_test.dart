import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/workflow_gate.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/ui_spinner.dart';

// ─── The resolve loader wears the caller's brand ──────────────────────────────
//
// The loader is painted while GET /api/v1/workflows/:id is in flight, so the
// workflow's OWN appearance cannot be known yet — it is what the request is
// fetching. The caller's configured appearance is the closest thing that
// exists, and using it stops a dark or brand-coloured flow repainting the
// instant it opens.

Color _spinnerColour(WidgetTester tester) => tester
    .widget<UiSpinner>(find.byType(UiSpinner))
    .color!;

// The pulse loader animates forever (flutter_animate `repeat()`), so the widget
// is unmounted before the test ends or its restart timer is still pending at
// teardown and the test fails on that rather than on the colour.
Future<void> _pump(WidgetTester tester, VerificationConfig config) async {
  await tester.pumpWidget(
    MaterialApp(home: WorkflowResolveLoader(config: config)),
  );
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  group('WorkflowResolveLoader', () {
    const brand = Color(0xFFEA5B0C);

    testWidgets('takes the configured primary colour', (tester) async {
      await _pump(
        tester,
        const VerificationConfig(
          apiKey: 'pk_test_x',
          workflowId: 'wf_x',
          appearance: VerificationAppearance(primaryColor: brand),
        ),
      );
      expect(_spinnerColour(tester), brand);
      await _unmount(tester);
    });

    testWidgets('a dark flow loads on the dark scheme', (tester) async {
      await _pump(
        tester,
        const VerificationConfig(
          apiKey: 'pk_test_x',
          workflowId: 'wf_x',
          appearance: VerificationAppearance(theme: VerificationThemeMode.dark),
        ),
      );
      expect(_spinnerColour(tester), UiColorScheme.dark.primary);
      await _unmount(tester);
    });

    testWidgets('a brand colour survives into a dark flow', (tester) async {
      await _pump(
        tester,
        const VerificationConfig(
          apiKey: 'pk_test_x',
          workflowId: 'wf_x',
          appearance: VerificationAppearance(
            primaryColor: brand,
            theme: VerificationThemeMode.dark,
          ),
        ),
      );
      expect(_spinnerColour(tester), brand);
      await _unmount(tester);
    });

    testWidgets('a dark override wins over the top-level brand', (tester) async {
      const darkBrand = Color(0xFF12B981);
      await _pump(
        tester,
        const VerificationConfig(
          apiKey: 'pk_test_x',
          workflowId: 'wf_x',
          appearance: VerificationAppearance(
            primaryColor: brand,
            theme: VerificationThemeMode.dark,
            dark: VerificationAppearance(primaryColor: darkBrand),
          ),
        ),
      );
      expect(_spinnerColour(tester), darkBrand);
      await _unmount(tester);
    });

    testWidgets('no appearance keeps the built-in theme', (tester) async {
      await _pump(
        tester,
        const VerificationConfig(apiKey: 'pk_test_x', workflowId: 'wf_x'),
      );
      expect(_spinnerColour(tester), UiColorScheme.light.primary);
      await _unmount(tester);
    });
  });
}
