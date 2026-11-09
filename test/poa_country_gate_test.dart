import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/country_names.g.dart';
import 'package:toden_flutter/src/config/poa_country_gate.dart';

// The Proof of Address step's country (user decisions 2026-09-08 and
// 2026-11-07). Mirrors the web SDK's lib/poa-country-gate.test.ts and RN.
void main() {
  const world = ['NG', 'GH', 'GB'];
  String? of({
    String? scope,
    String? selectedCountry,
    String? poaCountry,
    String? idCountry,
    List<String> offered = world,
  }) =>
      poaCountryOf(
        scope: scope,
        selectedCountry: selectedCountry,
        poaCountry: poaCountry,
        idCountry: idCountry,
        offered: offered,
      );

  test('starts from the ID country outside the address scope, and a pick replaces it', () {
    expect(of(selectedCountry: 'NG', idCountry: 'NG'), 'NG');
    expect(of(selectedCountry: 'NG', idCountry: 'NG', poaCountry: 'GB'), 'GB');
  });

  test('does not start from an ID country the org does not accept', () {
    expect(of(idCountry: 'KE'), isNull);
  });

  test('on the address scope only the declared country counts', () {
    expect(of(scope: 'address', selectedCountry: 'gh'), 'GH');
    expect(of(scope: 'address', idCountry: 'NG', poaCountry: 'NG'), isNull);
    expect(of(scope: 'address', selectedCountry: ' '), isNull);
  });

  test('one accepted country is a settled fact, not a choice', () {
    expect(of(scope: 'address', offered: const ['NG']), 'NG');
    expect(of(offered: const ['NG']), 'NG');
  });

  test('the offered list is the org list, unknown codes dropped, else the world', () {
    expect(poaOfferedCountries(const ['ng', 'XX', 'GH']), ['NG', 'GH']);
    expect(poaOfferedCountries(const []).length, kCountryNames.length);
  });

  test('the PoA screen gates Continue on it', () {
    final src = File('lib/src/providers/poa_step.dart').readAsStringSync();
    expect(src, contains('poaCountryOf('));
    final screen = File('lib/src/screens/proof_of_address_screen.dart').readAsStringSync();
    expect(screen, contains('poaStepCountry(config, state)'));
    // The gate sits on the button, not merely computed.
    expect(screen,
        matches(RegExp(r"label: context\.verificationText\('common\.continue'\),\s*onPressed: !_uploading && poaCountry != null")));
  });
}
