import 'package:flutter/material.dart';

// ─── How a business document group arrives ───────────────────────────────────
//
// Moving forward, the open card comes 16px DOWN into place from where the next
// group's card was tucked above it; moving back, it comes 16px up from where
// the previous card was below. The tucked cards only fade in ([slide] false).
// 300ms, ease-out, with a fade. Keyed by its caller, so it plays afresh each
// time the applicant moves. Nothing plays before the first move (the step's own
// entrance is enough); when the system asks for less motion it only fades.
//
// MIRRORS the web SDK's animate-slide-down / animate-slide-up / animate-fade-in
// in GroupStack.

class BusinessDocumentEntrance extends StatefulWidget {
  const BusinessDocumentEntrance({
    super.key,
    required this.direction,
    this.slide = true,
    required this.child,
  });

  /// 1 = arrived by moving forward, -1 = by moving back, 0 = no move yet.
  final int direction;

  /// Whether it moves as well as fades.
  final bool slide;
  final Widget child;

  @override
  State<BusinessDocumentEntrance> createState() =>
      _BusinessDocumentEntranceState();
}

class _BusinessDocumentEntranceState extends State<BusinessDocumentEntrance>
    with SingleTickerProviderStateMixin {
  static const _distance = 16.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  bool _started = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = MediaQuery.disableAnimationsOf(context);
    if (widget.direction == 0) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faded = FadeTransition(opacity: _curve, child: widget.child);
    if (!widget.slide || _still) return faded;
    // Forward comes down from above (negative y), back up from below.
    final from = -widget.direction * _distance;
    return AnimatedBuilder(
      animation: _curve,
      child: faded,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, from * (1 - _curve.value)),
        child: child,
      ),
    );
  }
}
