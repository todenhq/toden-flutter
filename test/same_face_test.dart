import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/capture_hints.dart';
import 'package:toden_flutter/src/config/same_face.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';

const front = [
  'INDEPENDENT NATIONAL ELECTORAL COMMISSION',
  'PERMANENT VOTER CARD',
  'NAME ADA OBI',
  'OCCUPATION TRADER',
  'DELIM 12 03 45',
];

void main() {
  test('recognises the front held up again, misread words and all', () {
    expect(
      stillSameFace(wordsOf(front), const [
        'INDEPENDENT NATI0NAL ELECTORAL COMMISSION',
        'PERMANENT VOTER CARD',
        'NAME OBI',
        'OCCUPATION TRADER',
      ]),
      isTrue,
    );
  });

  test('lets a back through, even one sharing a word or two', () {
    expect(
      stillSameFace(wordsOf(front), const [
        'This card is the property of the commission',
        'If found return to the nearest office',
      ]),
      isFalse,
    );
  });

  test('says nothing about a front with too little text', () {
    expect(stillSameFace(wordsOf(const ['VOTER CARD']), const ['VOTER CARD']), isFalse);
    expect(stillSameFace(null, front), isFalse);
  });

  test('the hint tells the person what to do', () {
    expect(
      documentHintText(DocumentHint.showBack, label: 'PVC'),
      "That's still the front. Turn your PVC over",
    );
  });
}
