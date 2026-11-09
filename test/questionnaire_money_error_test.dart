import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/screens/questionnaire_screen.dart';

// A required money field left empty used to print "This field is required."
// under the whole row, left-aligned, so it sat under the currency control and
// read as if the currency were missing. The amount is what is missing.

const _volume = QuestionnaireField(
  key: 'monthly_volume',
  label: 'What is your expected monthly transaction volume?',
  type: QuestionnaireFieldType.money,
  required: true,
  placeholder: 'e.g. 250,000',
  currencies: ['NGN', 'USD'],
);

void main() {
  testWidgets('a missing amount is marked on the amount, not under the currency', (tester) async {
    final container = ProviderContainer(overrides: [
      verificationConfigProvider.overrideWithValue(const VerificationConfig(
        apiKey: 'pk_test_stub',
        country: 'NG',
        consentStep: false,
        questionnaire: QuestionnaireConfig(fields: [_volume]),
      )),
      kYCNotifierProvider.overrideWith(VerificationNotifier.new),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [UiColorScheme.light]),
        home: const Scaffold(body: SingleChildScrollView(child: QuestionnaireScreen())),
      ),
    ));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final message = find.text('This field is required.');
    expect(message, findsOneWidget);
    final amount = tester.widget<UiInput>(find.byType(UiInput));
    expect(amount.errorText, 'This field is required.');
    // The message sits inside the amount input, to the right of the currency.
    expect(find.descendant(of: find.byType(UiInput), matching: message), findsOneWidget);
  });
}
