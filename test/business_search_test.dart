import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/business_search.dart';
import 'package:toden_flutter/src/config/registration_hint.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// ─── Search by company name: the request, the refusals, the workflow switch ──
//
// Ported from the web SDK's lib/business-search.test.ts and the RN SDK's
// businessSearch.test.ts; keep the three in lockstep.

VerificationApiException err(String code, [String? message]) =>
    VerificationApiException(statusCode: 400, error: code, message: message);

void main() {
  group('business search request', () {
    test('sends the attempt session, the same id the register check sends', () {
      final params = businessSearchQueryParameters(
        country: 'GH',
        query: 'Acme',
        limit: 50,
        sessionId: 'sess_1',
      );
      expect(params['sessionId'], 'sess_1');
      expect(params['country'], 'GH');
      expect(params['limit'], 50);
    });

    test('is what the search screen sends', () {
      final src =
          File('lib/src/screens/business_search.dart').readAsStringSync();
      expect(src, contains('ref.read(kYCNotifierProvider).sessionId'));
      expect(src, contains('sessionId: sessionId'));
      expect(File('lib/src/services/api_service.dart').readAsStringSync(),
          contains('queryParameters: businessSearchQueryParameters('));
    });

    test('leaves the session out when there is none', () {
      final params =
          businessSearchQueryParameters(country: 'NG', query: 'Acme');
      expect(params.containsKey('sessionId'), isFalse);
    });
  });

  group('business search refusals', () {
    test('moves to number entry on every refusal, with the server message', () {
      for (final code in const [
        'business_search_disabled',
        'session_required',
        'insufficient_credits',
        'search_limit_reached',
        'pricing_not_configured',
      ]) {
        expect(kBusinessSearchRefusals, contains(code));
        final refusal =
            businessSearchRefusal(err(code, 'Enter the registration number.'));
        expect(refusal?.code, code);
        expect(refusal?.message, 'Enter the registration number.');
      }
      expect(businessSearchRefusal(err('session_required'))?.message, isNull);
    });

    test('keeps the search for an outage or a throttle', () {
      expect(businessSearchRefusal(err('search_unavailable')), isNull);
      expect(businessSearchRefusal(err('search_rate_limited')), isNull);
      expect(businessSearchRefusal(Exception('network')), isNull);
    });
  });

  group('workflow switch for search by name', () {
    test('is on unless the workflow switched it off', () {
      expect(nameSearchOffered(null), isTrue);
      expect(
          nameSearchOffered(WorkflowBusinessConfig.fromJson({'country': 'NG'})),
          isTrue);
      expect(
          nameSearchOffered(WorkflowBusinessConfig.fromJson(
              {'country': 'NG', 'nameSearch': false})),
          isFalse);
    });
  });

  group('business document labels', () {
    const newKeys = {
      'business_registration': 'Business registration certificate',
      'good_standing_certificate': 'Certificate of good standing',
      'registry_extract':
          'Official company extract or profile from the registrar',
      'annual_return': 'Latest annual return',
      'register_of_directors': 'Register of directors',
      'shareholder_register': 'Register of shareholders',
      'share_certificate': 'Share certificate',
      'ubo_declaration': 'Beneficial ownership declaration',
      'power_of_attorney': 'Power of attorney',
      'authorization_letter': 'Letter of authorisation',
      'financial_statements': 'Financial statements or audited accounts',
    };

    test('labels every key the server catalogue may send', () {
      newKeys.forEach((key, label) {
        expect(businessDocumentLabel(key), label);
      });
      expect(kBusinessDocumentLabels, hasLength(18));
      expect(kBusinessDocumentLabels['memart'],
          'Memorandum and articles / company constitution');
      expect(kBusinessDocumentLabels['tax_document'],
          'Tax registration or clearance certificate');
      expect(kBusinessDocumentLabels['regulatory_license'],
          'Regulatory licence or permit');
    });
  });

  group('Ghana registration numbers', () {
    test('uses the Registrar of Companies prefixes', () {
      final hint = registrationNumberHint('GH', businessProduct('business'));
      expect(hint.placeholder, 'e.g. CS043840225');
      expect(hint.tip, contains('CS for a company, BN for a business name'));
      expect(hint.isValidFormat, isNull);
    });
  });

  group('the first screen of the business step', () {
    ({bool numberEntry, bool search, bool card}) view({
      bool searchOffered = true,
      bool refused = false,
      bool manualEntry = false,
      bool picked = false,
    }) =>
        businessPickView(
          searchOffered: searchOffered,
          refused: refused,
          manualEntry: manualEntry,
          picked: picked,
        );

    test('asks for the registration number when search is off, refused or skipped', () {
      for (final picked in [false, true]) {
        for (final v in [
          view(searchOffered: false, picked: picked),
          view(refused: true, picked: picked),
          view(manualEntry: true, picked: picked),
        ]) {
          expect(v, (numberEntry: true, search: false, card: false));
        }
      }
    });

    test('shows the search, then the card once a company is named', () {
      expect(view(), (numberEntry: false, search: true, card: false));
      expect(view(picked: true), (numberEntry: false, search: false, card: true));
    });
  });
}
