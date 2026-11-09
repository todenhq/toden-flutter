import 'dart:async';

import 'package:flutter/material.dart';

import '../config/document_people.dart';
import '../config/theme.dart';
import 'document_being_read.dart';
import 'icons/icons.dart';

/// The key-people step while the company's documents are read for the people
/// they name (config/document_people.dart). Fills the step so the person
/// waiting sees what is happening and why: each person the documents name is
/// lifted off the page into a list beside it.
///
/// [KeyPeopleReadingGate] decides when it shows: when the step opens while a
/// read is in flight, then "Found N people" for a moment before the list. A
/// read that runs past [kReadingGiveUp] gives way too, so nobody is held here:
/// it carries on and its people are merged when it lands.
/// Mirrors the web and React Native SDKs' reading screens.
class KeyPeopleReadingGate extends StatefulWidget {
  const KeyPeopleReadingGate({
    super.key,
    required this.reading,
    required this.found,
    required this.child,
  });

  final bool reading;
  final int found;
  final Widget child;

  @override
  State<KeyPeopleReadingGate> createState() => _KeyPeopleReadingGateState();
}

enum _Phase { reading, found, hidden }

class _KeyPeopleReadingGateState extends State<KeyPeopleReadingGate> {
  late _Phase _phase = widget.reading ? _Phase.reading : _Phase.hidden;
  Timer? _hold;
  Timer? _giveUp;

  @override
  void initState() {
    super.initState();
    if (_phase == _Phase.reading) {
      _giveUp = Timer(kReadingGiveUp, () {
        if (mounted && _phase == _Phase.reading) {
          setState(() => _phase = _Phase.hidden);
        }
      });
    }
  }

  @override
  void didUpdateWidget(KeyPeopleReadingGate old) {
    super.didUpdateWidget(old);
    if (_phase == _Phase.reading && !widget.reading) {
      _giveUp?.cancel();
      if (widget.found > 0) {
        _phase = _Phase.found;
        _hold = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _phase = _Phase.hidden);
        });
      } else {
        _phase = _Phase.hidden;
      }
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _giveUp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.hidden) return widget.child;
    return KeyPeopleReadingScreen(
        found: _phase == _Phase.found ? widget.found : null);
  }
}

class KeyPeopleReadingScreen extends StatefulWidget {
  const KeyPeopleReadingScreen({super.key, required this.found});

  /// People found, once the read has finished; null while reading.
  final int? found;

  @override
  State<KeyPeopleReadingScreen> createState() => _KeyPeopleReadingScreenState();
}

class _KeyPeopleReadingScreenState extends State<KeyPeopleReadingScreen> {
  int _stage = 0;
  bool _slow = false;
  late final Timer _tick;
  late final Timer _later;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 3500),
        (_) => setState(() => _stage = (_stage + 1) % kReadingStages.length));
    _later =
        Timer(const Duration(seconds: 20), () => setState(() => _slow = true));
  }

  @override
  void dispose() {
    _tick.cancel();
    _later.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final done = widget.found != null;
    final status =
        done ? documentPeopleFoundTitle(widget.found!) : kReadingStages[_stage];
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DocumentBeingRead(found: widget.found),
            const SizedBox(height: 28),
            Semantics(
              header: true,
              child: Text(kReadingTitle,
                  textAlign: TextAlign.center,
                  style: text.heading2.copyWith(color: colors.textDark)),
            ),
            const SizedBox(height: 8),
            Text(kReadingDescription,
                textAlign: TextAlign.center,
                style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              label: status,
              excludeSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  UiIcon(done ? UiIcons.check : UiIcons.scanLine,
                      size: 16, color: colors.primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(status,
                        style: text.bodySmall.copyWith(
                            color: colors.textDark,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
            if (!done && _slow) ...[
              const SizedBox(height: 24),
              Text(kReadingSlow,
                  textAlign: TextAlign.center,
                  style: text.bodySmall.copyWith(color: colors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
