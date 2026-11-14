import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/services/contact_errors.dart';

// A work-address-only workflow refuses a free-provider email with the usual
// invalid_destination and a reason. Every other refusal keeps its copy.
void main() {
  VerificationApiException refusal(String error, [Map<String, dynamic>? details]) =>
      VerificationApiException(statusCode: 400, error: error, details: details);

  test('asks for a work address when the server wants one', () {
    expect(
      describeSendError(refusal('invalid_destination', {'reason': 'corporate_email_required'})),
      'Use your work email address. Personal email services such as Gmail are not accepted here.',
    );
  });

  test('keeps the old copy for any other invalid destination', () {
    const old = 'That does not look valid. Please check and try again.';
    expect(describeSendError(refusal('invalid_destination')), old);
    expect(describeSendError(refusal('invalid_destination', {'reason': 'something_else'})), old);
  });

  test('keeps the rate limit copy', () {
    expect(describeSendError(refusal('send_rate_limited')),
        'Too many codes requested. Please wait a while and try again.');
  });
}
