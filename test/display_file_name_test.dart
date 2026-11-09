import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/utils/display_file_name.dart';

// The same vectors as the web SDK's lib/display-file-name.test.ts.

void main() {
  test('drops names that are a random id', () {
    expect(displayFileName('940f84e9-18c6-4894-accc-3621f5b1a2c3.jpg'), isNull);
    expect(displayFileName('940F84E918C64894ACCC3621F5B1A2C3.PNG'), isNull);
    expect(displayFileName('5f2b9c0d8e7a6b5c4d3e2f1a0b9c8d7e'), isNull);
  });

  test('keeps ordinary names', () {
    expect(displayFileName('IMG_1234.jpg'), 'IMG_1234.jpg');
    expect(displayFileName('memart.pdf'), 'memart.pdf');
    expect(displayFileName('cac-certificate 2024.pdf'), 'cac-certificate 2024.pdf');
  });

  test('treats nothing as nothing', () {
    expect(displayFileName(null), isNull);
    expect(displayFileName(''), isNull);
  });
}
