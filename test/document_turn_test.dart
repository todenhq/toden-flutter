import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/document_turn.dart';
import 'package:toden_flutter/src/screens/document_turn_reading.dart';

// A NIN slip framed upright on a phone held upright. The rule is mirrored in
// the React Native SDK (capture/documentTurn.ts) with the same names and
// values; these pin the Flutter side.

void main() {
  group('turnsDocument', () {
    test('turns a NIN slip on a phone held upright', () {
      expect(turnsDocument(kNinSlipGuideAspect, 393 / 852), isTrue);
    });

    test('never turns a card or a passport page', () {
      expect(turnsDocument(kCardGuideAspect, 393 / 852), isFalse);
      expect(turnsDocument(kPassportGuideAspect, 393 / 852), isFalse);
    });

    test('keeps a slip landscape on a wide or square view', () {
      expect(turnsDocument(kNinSlipGuideAspect, 1024 / 768), isFalse);
      expect(turnsDocument(kNinSlipGuideAspect, 1), isFalse);
      expect(turnsDocument(kNinSlipGuideAspect, 0), isFalse);
    });

    test('the threshold is 1.8', () {
      expect(turnsDocument(1.8, 0.5), isTrue);
      expect(turnsDocument(1.79, 0.5), isFalse);
    });
  });

  test('the guide stands upright when turned', () {
    expect(screenGuideAspect(2.07, true), closeTo(1 / 2.07, 1e-9));
    expect(screenGuideAspect(2.07, false), 2.07);
  });

  group('documentCropGuide', () {
    test('stands a NIN slip upright on a phone, as the camera guide does', () {
      final crop = documentCropGuide(kNinSlipGuideAspect, 393 / 852);
      expect(crop.turned, isTrue);
      expect(crop.aspect, closeTo(1 / kNinSlipGuideAspect, 1e-9));
    });

    test('keeps cards and passports landscape on a phone', () {
      expect(documentCropGuide(kCardGuideAspect, 393 / 852),
          (aspect: kCardGuideAspect, turned: false));
      expect(documentCropGuide(kPassportGuideAspect, 393 / 852),
          (aspect: kPassportGuideAspect, turned: false));
    });

    test('keeps a NIN slip landscape on a screen wider than tall', () {
      expect(documentCropGuide(kNinSlipGuideAspect, 1024 / 768),
          (aspect: kNinSlipGuideAspect, turned: false));
    });
  });

  group('undoDegrees', () {
    test('undoes the turn that read the slip', () {
      expect(undoDegrees(1), 90);
      expect(undoDegrees(3), 270);
    });

    test('assumes the default direction (top facing right) otherwise', () {
      // Top facing right: put back with 90 degrees counter-clockwise.
      expect(kDefaultReadTurn, 3);
      expect(undoDegrees(null), 270);
      expect(undoDegrees(0), 270);
      expect(undoDegrees(2), 270);
    });
  });

  group('DocumentTurnReader', () {
    test('alternates three and one quarter turns, default first', () {
      final reader = DocumentTurnReader();
      expect([for (var i = 0; i < 4; i++) reader.nextTurn()], [3, 1, 3, 1]);
    });

    test('keeps the turn that identified the slip', () {
      final reader = DocumentTurnReader();
      reader.observe(1, identified: true);
      expect([for (var i = 0; i < 3; i++) reader.nextTurn()], [1, 1, 1]);
      expect(reader.identifiedTurn, 1);
      expect(reader.undoDegreesForCapture, 90);
    });

    test('a frame with nothing readable says nothing', () {
      final reader = DocumentTurnReader()..observe(3, identified: true);
      reader
        ..observe(3, identified: null)
        ..observe(3, identified: null)
        ..observe(3, identified: null);
      expect(reader.turns, [3]);
    });

    test('goes back to both turns after two misses at the kept turn', () {
      final reader = DocumentTurnReader()..observe(1, identified: true);
      reader.observe(1, identified: false);
      expect(reader.turns, [1]);
      reader.observe(1, identified: false);
      expect(reader.turns, [3, 1]);
      // Still remembered for turning the photo back.
      expect(reader.identifiedTurn, 1);
    });

    test('a miss at another turn does not count against the kept one', () {
      final reader = DocumentTurnReader()..observe(3, identified: true);
      reader
        ..observe(1, identified: false)
        ..observe(1, identified: false);
      expect(reader.turns, [3]);
    });

    test('undoes the default direction before anything identified', () {
      expect(DocumentTurnReader().undoDegreesForCapture, 270);
    });

    test('reset forgets the turn', () {
      final reader = DocumentTurnReader()..observe(1, identified: true);
      reader.reset();
      expect(reader.turns, [3, 1]);
      expect(reader.identifiedTurn, isNull);
    });
  });

  group('DocumentTurnReading', () {
    test('turns only for a long document in a tall view', () {
      final reading = DocumentTurnReading();
      expect(reading.update(kCardGuideAspect, const Size(393, 852)), isFalse);
      expect(reading.turned, isFalse);
      expect(reading.captureUndoDegrees, 0);
      expect(reading.update(kNinSlipGuideAspect, const Size(393, 852)), isTrue);
      expect(reading.turned, isTrue);
      expect(reading.captureUndoDegrees, 270);
      expect(reading.update(kNinSlipGuideAspect, const Size(393, 852)), isFalse);
    });

    test('ignores a stale frame once a turn has identified the slip', () {
      final reading = DocumentTurnReading()
        ..update(kNinSlipGuideAspect, const Size(393, 852));
      expect(reading.counts(3), isTrue);
      expect(reading.counts(1), isTrue);
      reading.observe(1, identified: true);
      expect(reading.counts(1), isTrue);
      expect(reading.counts(3), isFalse);
      expect(reading.captureUndoDegrees, 90);
    });

    test('an upright read never moves the turn', () {
      final reading = DocumentTurnReading()
        ..update(kNinSlipGuideAspect, const Size(393, 852));
      reading.observe(0, identified: true);
      expect(reading.captureUndoDegrees, 270);
    });
  });
}
