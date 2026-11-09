import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/id_types.dart';
import 'package:toden_flutter/src/config/nin_slip.dart';

// NIN and its slip, merged (2026-11-07). Mirrors the web SDK's
// lib/nin-slip.test.ts.
List<String> _ids(String country, List<String> keys) =>
    withoutNinBesideSlip(country, keys, (k) => k);

void main() {
  test('offers only the slip when a workflow lists both', () {
    expect(_ids('NG', ['bvn', 'nin', 'nin-slip']), ['bvn', 'nin-slip']);
  });

  test('leaves NIN alone without the slip, and other countries alone', () {
    expect(_ids('NG', ['bvn', 'nin']), ['bvn', 'nin']);
    expect(_ids('GH', ['nin', 'nin-slip']), ['nin', 'nin-slip']);
  });

  test('the slip is named as NIN', () {
    expect(curatedIdType('NG', 'nin-slip')?.label, 'NIN (Slip)');
  });
}
