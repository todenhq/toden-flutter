import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/theme.dart';
import 'document_being_read_parts.dart';

/// A page being read (KeyPeopleReadingScreen): a beam sweeps down it, and as
/// it reaches each person the line lights up and a card for them lifts off the
/// page into the stack beside it. Finished, the cards settle with a tick, one
/// per person found (up to three). Decorative, so it is excluded from
/// semantics. Under reduced motion it holds still with the people shown.
/// Mirrors the web and React Native SDKs' illustration (the same shares of
/// the same 3.6s sweep).
class DocumentBeingRead extends StatefulWidget {
  const DocumentBeingRead({super.key, required this.found});

  /// People found, once the read has finished; null while reading.
  final int? found;

  @override
  State<DocumentBeingRead> createState() => _DocumentBeingReadState();
}

const double _pageHeight = 208;
const double _cycleMs = 3600;

/// The rows that name a person: top on the page, when the beam reaches them
/// (share of the sweep), and the widths of the card's name and role bars.
const List<(double, double, double, double)> _people = [
  (68, 0.37, 0.62, 0.38),
  (120, 0.58, 0.74, 0.46),
  (172, 0.79, 0.56, 0.32),
];

/// Plain text lines: top on the page and width (share of the line).
final _filler = <(double, double)>[(36, 0.70), (48, 0.86), (92, 0.64)] +
    <(double, double)>[(104, 0.80), (144, 0.58), (156, 0.76), (196, 0.66)];

class _DocumentBeingReadState extends State<DocumentBeingRead>
    with SingleTickerProviderStateMixin {
  /// Sweeps since the screen opened; a card waits for its first sweep.
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker(
      (elapsed) => _time.value = elapsed.inMilliseconds / _cycleMs);

  bool get _running =>
      widget.found == null && !MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DocumentBeingRead old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_running && !_ticker.isActive) _ticker.start();
    if (!_running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _running;
    final found = widget.found;
    final shown = found == null
        ? _people
        : _people.take(found.clamp(1, _people.length)).toList();
    return ExcludeSemantics(
      child: SizedBox(
        width: 288,
        height: 224,
        child: ValueListenableBuilder<double>(
          valueListenable: _time,
          builder: (context, time, _) =>
              Stack(clipBehavior: Clip.none, children: [
            Positioned(
                left: 8, top: 8, child: _Page(time: time, running: running)),
            for (final p in shown)
              ReadingPersonCard(
                  person: p, time: time, running: running, done: found != null),
          ]),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.time, required this.running});
  final double time;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final sweep = time % 1;
    return Container(
      width: 144,
      height: _pageHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Stack(children: [
        Positioned(
            left: 16,
            top: 16,
            width: 72,
            height: 10,
            child: readingBar(colors.primary.withValues(alpha: 0.35), 5)),
        for (final (top, w) in _filler)
          Positioned(
              left: 16,
              top: top,
              width: 112 * w,
              height: 6,
              child:
                  readingBar(colors.textSecondary.withValues(alpha: 0.2), 3)),
        for (final (top, at, name, _) in _people)
          Positioned(
            left: 10,
            right: 10,
            top: top - 7,
            height: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: colors.primary.withValues(
                    alpha: running && time >= at
                        ? readingKeys((time - at) % 1, const [0, 0.06, 0.24],
                            const [0, 0.16, 0])
                        : 0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(alpha: 0.5))),
                  const SizedBox(width: 6),
                  SizedBox(
                      width: 100 * name,
                      height: 6,
                      child: readingBar(
                          colors.primary.withValues(alpha: 0.55), 3)),
                ]),
              ),
            ),
          ),
        if (running)
          Positioned(
            left: 0,
            right: 0,
            top: -40 + (_pageHeight + 40) * sweep,
            height: 40,
            child: Opacity(
              opacity: readingKeys(
                  sweep, const [0, 0.06, 0.92, 1], const [0, 1, 1, 0]),
              child: Stack(children: [
                Positioned.fill(
                    child: ColoredBox(
                        color: colors.primary.withValues(alpha: 0.14))),
                Positioned(
                    left: 0,
                    right: 0,
                    top: 19,
                    height: 2,
                    child: ColoredBox(
                        color: colors.primary.withValues(alpha: 0.75))),
              ]),
            ),
          ),
      ]),
    );
  }
}
