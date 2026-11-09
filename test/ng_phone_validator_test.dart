import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/services/validators.dart';

void main() {
  for (final idType in ['phone-number', 'nin-phone']) {
    test('$idType accepts every way a Nigerian number is typed', () {
      for (final typed in [
        '08031234567',
        '+234 803 123 4567',
        '2348031234567',
        '803 123 4567',
      ]) {
        expect(validateIdNumber(typed, 'NG', idType).isValid, isTrue);
      }
      expect(validateIdNumber('0803123456', 'NG', idType).isValid, isFalse);
      expect(validateIdNumber('01234567890', 'NG', idType).isValid, isFalse);
      expect(validateIdNumber('0803ABC4567', 'NG', idType).isValid, isFalse);
    });
  }

  test('brings a number to the local form the server sends', () {
    expect(normaliseNgPhone('+234 803 123 4567'), '08031234567');
    expect(normaliseNgPhone('803 123 4567'), '08031234567');
  });
}
