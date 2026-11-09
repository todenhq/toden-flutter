import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// The pieces of DocumentBeingRead: the keyframe helper, a bar, and the card a
// person becomes as they are lifted off the page.

/// Linear keyframes: the value at [p] between [stops] (ascending, 0..1).
double readingKeys(double p, List<double> stops, List<double> values) {
  if (p <= stops.first) return values.first;
  for (var i = 1; i < stops.length; i++) {
    if (p <= stops[i]) {
      final t = (p - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return values[i - 1] + (values[i] - values[i - 1]) * t;
    }
  }
  return values.last;
}

/// A rounded bar standing in for a line of text.
Widget readingBar(Color color, double r) => DecoratedBox(
    decoration:
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(r)));

/// One person lifted off the page, level with the row that named them.
class ReadingPersonCard extends StatelessWidget {
  const ReadingPersonCard(
      {super.key,
      required this.person,
      required this.time,
      required this.running,
      required this.done});
  final (double, double, double, double) person;
  final double time;
  final bool running;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final (top, at, name, role) = person;
    var opacity = 1.0, dx = 0.0, scale = 1.0;
    if (running) {
      if (time < at) {
        opacity = 0;
      } else {
        final p = (time - at) % 1;
        opacity =
            readingKeys(p, const [0, 0.09, 0.72, 0.86], const [0, 1, 1, 0]);
        dx = readingKeys(
            p, const [0, 0.09, 0.14, 0.72, 0.86], const [-56, 4, 0, 0, 8]);
        scale = readingKeys(p, const [0, 0.09, 0.14], const [0.7, 1.03, 1]);
      }
    }
    return Positioned(
      left: 112,
      top: top - 18,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 160,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 10,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: colors.primary),
                  child: UiIcon(done ? UiIcons.check : UiIcons.user,
                      size: 16, color: colors.onPrimary),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 96 * name,
                        height: 8,
                        child: readingBar(
                            colors.textDark.withValues(alpha: 0.7), 4)),
                    const SizedBox(height: 6),
                    SizedBox(
                        width: 96 * role,
                        height: 6,
                        child: readingBar(
                            colors.primary.withValues(alpha: 0.4), 3)),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
