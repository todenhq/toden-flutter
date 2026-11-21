import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/app_country.dart';
import 'package:toden_flutter/src/config/verification_config.dart';

// A workflow that verifies IDs from Nigeria, Ghana and Kenya, opening on
// Nigeria, as it reaches the rule: already merged over the app's config, so
// its `country` is the workflow's own. Mirrors the web SDK's app-country test.
VerificationConfig flow({bool lockCountry = false}) => VerificationConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      lockCountry: lockCountry,
      countries: const [
        WorkflowCountryOption(country: 'NG', idTypes: ['nin']),
        WorkflowCountryOption(country: 'GH', idTypes: ['ghana-card']),
        WorkflowCountryOption(country: 'KE'),
      ],
    );

void main() {
  test('opens the picker on the country the app passed, keeping every country on offer', () {
    final out = applyAppCountry(flow(), 'GH');
    expect(out.country, 'GH');
    expect(out.appCountry, 'GH');
    expect(out.countries, hasLength(3));
  });

  test('offers that country alone when locked, with its own ID types, so no picker shows', () {
    final out = applyAppCountry(flow(lockCountry: true), ' gh ');
    expect(out.country, 'GH');
    expect(out.countries, hasLength(1));
    expect(out.countries!.single.idTypes, ['ghana-card']);
  });

  test('changes nothing for a country the flow does not offer, locked or not', () {
    final open = flow();
    expect(identical(applyAppCountry(open, 'ZA'), open), isTrue);
    final locked = flow(lockCountry: true);
    expect(identical(applyAppCountry(locked, 'ZA'), locked), isTrue);
  });

  test('changes nothing when the app passed no country, even with the lock set', () {
    final locked = flow(lockCountry: true);
    expect(identical(applyAppCountry(locked, null), locked), isTrue);
    expect(identical(applyAppCountry(locked, '  '), locked), isTrue);
  });

  test('leaves a single-country flow alone', () {
    const single = VerificationConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      lockCountry: true,
      countries: [WorkflowCountryOption(country: 'NG')],
    );
    expect(identical(applyAppCountry(single, 'GH'), single), isTrue);
    const propsOnly = VerificationConfig(apiKey: 'pk_test_x', country: 'NG');
    expect(identical(applyAppCountry(propsOnly, 'NG'), propsOnly), isTrue);
  });
}
