import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/business_search.dart';

// Mirrors the web and React Native SDKs' picked-business-name tests.
void main() {
  test('drops the sandbox outcome label, so the documents match the register', () {
    expect(pickedBusinessName('Transika Sandbox No Key People Ltd'), 'Transika Ltd');
    expect(pickedBusinessName('Transika Sandbox Ltd'), 'Transika Ltd');
    expect(pickedBusinessName('Transika Sandbox Late Shareholders Ltd'), 'Transika Ltd');
  });
  test('leaves a real company name alone', () {
    expect(pickedBusinessName('Sandbox Holdings Ltd'), 'Sandbox Holdings Ltd');
    expect(pickedBusinessName('GCB Bank PLC'), 'GCB Bank PLC');
  });
}
