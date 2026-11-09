import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/services/document_corners.dart';

// ─── The shared vectors (test/document_corners_vectors.json) ─────────────────
//
// One rule decides whether a document's corners allow a capture, and how much
// is kept around them, on all three SDKs. The web and React Native mirrors run
// the same file.

Map<String, dynamic> _vectors() => jsonDecode(
      File('test/document_corners_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

Offset _point(dynamic raw) {
  final m = raw as Map<String, dynamic>;
  return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
}

DocumentQuad? _quad(dynamic raw) {
  if (raw == null) return null;
  final m = raw as Map<String, dynamic>;
  return DocumentQuad(
    topLeft: _point(m['topLeft']),
    topRight: _point(m['topRight']),
    bottomRight: _point(m['bottomRight']),
    bottomLeft: _point(m['bottomLeft']),
  );
}

Rect _rect(dynamic raw) {
  final m = raw as Map<String, dynamic>;
  double v(String k) => (m[k] as num).toDouble();
  return Rect.fromLTRB(v('left'), v('top'), v('right'), v('bottom'));
}

const _problemNames = {
  DocumentCornersProblem.noDocument: 'no_document',
  DocumentCornersProblem.cornerCutOff: 'corner_cut_off',
  DocumentCornersProblem.tooClose: 'too_close',
};

void main() {
  final data = _vectors();

  test('the constants match the shared vectors', () {
    expect(kCornerBleed, data['bleed']);
    expect(kCornerEdgeEpsilon, data['edgeEpsilon']);
    expect(kCornerMinAreaFraction, data['minAreaFraction']);
  });

  group('cornersProblem (shared vectors)', () {
    for (final raw in data['problems'] as List) {
      final v = raw as Map<String, dynamic>;
      test(v['name'] as String, () {
        final problem = cornersProblem(_quad(v['quad']), _rect(v['visible']));
        expect(problem == null ? null : _problemNames[problem], v['expected']);
      });
    }
  });

  group('bleedCropRect (shared vectors)', () {
    for (final raw in data['crops'] as List) {
      final v = raw as Map<String, dynamic>;
      test(v['name'] as String, () {
        final frame = v['frame'] as Map<String, dynamic>;
        final e = v['expected'] as Map<String, dynamic>;
        final crop = bleedCropRect(
          _quad(v['quad'])!,
          Size((frame['width'] as num).toDouble(),
              (frame['height'] as num).toDouble()),
        );
        expect(crop, CropRect(e['x'] as int, e['y'] as int,
            e['width'] as int, e['height'] as int));
      });
    }
  });

  group('visibleFrameRegion', () {
    test('a wider frame than the view loses its sides', () {
      final r = visibleFrameRegion(const Size(1000, 1000), const Size(750, 1000));
      expect(r.left, closeTo(0.125, 1e-9));
      expect(r.right, closeTo(0.875, 1e-9));
      expect(r.top, 0);
      expect(r.bottom, 1);
    });

    test('a taller frame than the view loses its top and bottom', () {
      final r = visibleFrameRegion(const Size(900, 1600), const Size(900, 1200));
      expect(r.left, 0);
      expect(r.right, 1);
      expect(r.top, closeTo(0.125, 1e-9));
      expect(r.bottom, closeTo(0.875, 1e-9));
    });

    test('the same aspect shows the whole frame', () {
      expect(visibleFrameRegion(const Size(720, 1280), const Size(360, 640)),
          const Rect.fromLTRB(0, 0, 1, 1));
    });
  });

  group('DocumentQuad.fromList', () {
    test('reads eight numbers in corner order', () {
      final q = DocumentQuad.fromList([0.1, 0.2, 0.9, 0.2, 0.9, 0.7, 0.1, 0.7])!;
      expect(q.topLeft, const Offset(0.1, 0.2));
      expect(q.bottomRight, const Offset(0.9, 0.7));
    });

    test('refuses anything that is not eight finite numbers', () {
      expect(DocumentQuad.fromList(null), isNull);
      expect(DocumentQuad.fromList([0.1, 0.2]), isNull);
      expect(DocumentQuad.fromList([0, 0, 1, 0, 1, 1, 0, double.nan]), isNull);
      expect(DocumentQuad.fromList([0, 0, 1, 0, 1, 1, 0, '1']), isNull);
    });

    test('within maps into a larger frame', () {
      final q = DocumentQuad.fromList([0, 0, 1, 0, 1, 1, 0, 1])!
          .within(const Rect.fromLTWH(0, 0.125, 1, 0.75));
      expect(q.topLeft, const Offset(0, 0.125));
      expect(q.bottomLeft, const Offset(0, 0.875));
    });
  });

  group('exceedsGuide', () {
    const guide = Rect.fromLTRB(0.2, 0.2, 0.8, 0.6);

    test('a document up to 1.15 times the guide is within it', () {
      final q = DocumentQuad.fromList(
          [0.17, 0.18, 0.83, 0.18, 0.83, 0.62, 0.17, 0.62])!;
      expect(exceedsGuide(q, guide), isFalse);
    });

    test('wider or taller than 1.15 times the guide exceeds it', () {
      final wide = DocumentQuad.fromList(
          [0.1, 0.25, 0.9, 0.25, 0.9, 0.55, 0.1, 0.55])!;
      final tall = DocumentQuad.fromList(
          [0.3, 0.1, 0.7, 0.1, 0.7, 0.7, 0.3, 0.7])!;
      expect(exceedsGuide(wide, guide), isTrue);
      expect(exceedsGuide(tall, guide), isTrue);
    });
  });

  group('guideInFrame', () {
    test('maps the drawn guide through the part of the frame on screen', () {
      // A 400 x 800 view showing the middle half of the frame's width.
      final g = guideInFrame(
        const Rect.fromLTRB(100, 200, 300, 600),
        const Size(400, 800),
        const Rect.fromLTRB(0.25, 0, 0.75, 1),
      )!;
      expect(g.left, closeTo(0.375, 1e-9));
      expect(g.right, closeTo(0.625, 1e-9));
      expect(g.top, closeTo(0.25, 1e-9));
      expect(g.bottom, closeTo(0.75, 1e-9));
    });

    test('is null before the view has a size', () {
      expect(guideInFrame(Rect.zero, Size.zero, const Rect.fromLTRB(0, 0, 1, 1)),
          isNull);
    });
  });
}
