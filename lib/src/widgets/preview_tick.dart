import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// ─── The tick on the intro screens' pictures ──────────────────────────────────
//
// What the liveness camera shows when a gesture lands, on the pictures of the
// camera and the document scan that come before them: a light green cover
// (the success colour at 20%) and a green tick that pops up fast. The web
// SDK's GesturePreview and DocumentScanPreview draw the same two.

const Duration _pop = Duration(milliseconds: 160);
const Duration _show = Duration(milliseconds: 90);
const Duration _cover = Duration(milliseconds: 140);
const Curve _popCurve = Cubic(0.34, 1.56, 0.64, 1);

/// The light green cover, up while [on].
class PreviewPassCover extends StatelessWidget {
  const PreviewPassCover({super.key, required this.on, this.radius});

  final bool on;

  /// The corners of what it covers, when it is not clipped already.
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: _cover,
          curve: Curves.easeOut,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UiColors.success.withValues(alpha: 0.2),
              borderRadius: radius,
            ),
          ),
        ),
      );
}

/// The tick, popping up while [on].
class PreviewTick extends StatelessWidget {
  const PreviewTick({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: _show,
            child: AnimatedScale(
              scale: on ? 1 : 0.4,
              duration: _pop,
              curve: _popCurve,
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: UiColors.success,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 15,
                      offset: Offset(0, 10),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child:
                    const UiIcon(UiIcons.check, size: 28, color: Colors.white),
              ),
            ),
          ),
        ),
      );
}
