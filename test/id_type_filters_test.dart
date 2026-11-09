import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/chosen_only_ids.dart';
import 'package:toden_flutter/src/config/id_types.dart';
import 'package:toden_flutter/src/config/retired_id_types.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// The ID types the picker may offer from a served list. Mirrors the web SDK's
// lib/chosen-only-ids.test.ts and lib/retired-id-types.test.ts.

SdkConfigIdType _row(String idType, {String country = 'NG'}) => SdkConfigIdType(
      country: country,
      idType: idType,
      features: const SdkIdTypeFeatures(
        documentVerification: true,
        livenessCheck: true,
        govDbCheck: true,
      ),
    );

final _rows = [for (final id in ['bvn', 'nin', 'tax-id', 'vnin', 'passport']) _row(id)];

List<String> _keys(List<SdkConfigIdType> rows) => [for (final r in rows) r.idType];

VerificationConfig _config({
  String? workflowId,
  String? country,
  List<String>? idTypes,
  List<WorkflowCountryOption>? countries,
}) =>
    VerificationConfig(
      apiKey: 'pk_test_x',
      workflowId: workflowId,
      country: country,
      idTypes: idTypes,
      countries: countries,
    );

void main() {
  group('chosen-only IDs in a workflow', () {
    test('leaves them out of a country that lists no IDs', () {
      final config = _config(countries: const [WorkflowCountryOption(country: 'NG')]);
      expect(_keys(withoutUnchosenIdTypes(_rows, config)), ['bvn', 'nin', 'passport']);
    });

    test('keeps one the country lists by name', () {
      final listed = _config(countries: const [
        WorkflowCountryOption(country: 'NG', idTypes: ['bvn', 'vnin']),
      ]);
      expect(_keys(withoutUnchosenIdTypes(_rows, listed)), contains('vnin'));
      final top = _config(country: 'NG', idTypes: const ['tax-id']);
      expect(_keys(withoutUnchosenIdTypes(_rows, top)), contains('tax-id'));
    });

    test('applies on a workflow mount only; a mount in code lists its own IDs', () {
      final rows = [..._rows, _row('bvn-premium')];
      expect(_keys(servedIdTypes(rows, _config(workflowId: 'wf_1', country: 'NG'))),
          ['bvn', 'nin', 'passport']);
      expect(_keys(servedIdTypes(rows, _config(country: 'NG'))),
          ['bvn', 'nin', 'tax-id', 'vnin', 'passport']);
    });
  });

  group('retired ID types', () {
    test('names BVN Premium retired, and BVN not', () {
      expect(isRetiredIdType('NG', 'bvn-premium'), isTrue);
      expect(isRetiredIdType('ng', 'bvn-premium'), isTrue);
      expect(isRetiredIdType('ng', 'bvn'), isFalse);
    });

    test('is never served, on any mount', () {
      final rows = [_row('bvn'), _row('bvn-premium')];
      expect(_keys(servedIdTypes(rows, _config(country: 'NG'))), ['bvn']);
      expect(_keys(servedIdTypes(rows, _config(workflowId: 'wf_1'))), ['bvn']);
    });

    test('keeps its definition, so a run already holding it still resolves', () {
      expect(curatedIdType('NG', 'bvn-premium'), isNotNull);
    });

    test('the local fallback list drops it too', () {
      final src = File('lib/src/screens/id_type_screen.dart').readAsStringSync();
      expect(src, contains('!isRetiredIdType(country, c.key)'));
    });
  });
}
