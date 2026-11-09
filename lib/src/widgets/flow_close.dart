import 'package:flutter/widgets.dart';

// ─── The flow's own close, for a screen that covers the header ───────────────
//
// The sheet header's X closes the whole flow. A full-screen screen opened from
// inside a step (the photo camera) covers that header, so it draws its own X
// and closes through this: the same handler, so the host hears the same
// onClose either way.
//
// The flow provides it, set to null whenever the header shows no X (the host
// passed `disableClose`, or the step cannot be left), so a screen that reads it
// shows no close button exactly when the header shows none.
//
// Mirrors the React Native SDK's components/flowClose.ts.

class FlowClose extends InheritedWidget {
  /// Close the whole flow, or null when closing is turned off.
  final VoidCallback? onClose;

  const FlowClose({super.key, required this.onClose, required super.child});

  /// The flow's close handler, or null when there is none (closing is off, or
  /// the widget is mounted outside a flow). Read at the moment of use; nothing
  /// rebuilds on it.
  static VoidCallback? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FlowClose>()?.onClose;

  @override
  bool updateShouldNotify(FlowClose oldWidget) =>
      (oldWidget.onClose == null) != (onClose == null);
}
