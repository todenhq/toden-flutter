import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// ─── A column whose children overlap, painted in a chosen order ──────────────
//
// The business document carousel tucks the neighbouring groups' cards behind
// the open one: each child can be pulled up over the one before it
// ([TuckedSlot.overlap]) and painted above or below its neighbours
// ([TuckedSlot.layer]). A Column cannot overlap its children, and translating
// them would leave the pulled-up space empty at the bottom, so this lays them
// out itself: full width, top to bottom, the height being what is actually
// drawn. Hit testing follows the paint order, front first.

class TuckedStack extends MultiChildRenderObjectWidget {
  const TuckedStack({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTucked();
}

/// Places one child of a [TuckedStack].
class TuckedSlot extends ParentDataWidget<_TuckedParentData> {
  const TuckedSlot({
    super.key,
    this.overlap = 0,
    this.layer = 0,
    required super.child,
  });

  /// How far it is pulled up over the child before it.
  final double overlap;

  /// Paint order: higher layers are drawn over lower ones.
  final int layer;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _TuckedParentData;
    if (data.overlap == overlap && data.layer == layer) return;
    data
      ..overlap = overlap
      ..layer = layer;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => TuckedStack;
}

class _TuckedParentData extends ContainerBoxParentData<RenderBox> {
  double overlap = 0;
  int layer = 0;
}

class _RenderTucked extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TuckedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TuckedParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TuckedParentData) {
      child.parentData = _TuckedParentData();
    }
  }

  /// The children in paint order, back first.
  List<RenderBox> get _painted {
    final list = getChildrenAsList();
    // A stable sort, so children on one layer keep their order.
    return [
      for (final layer in {
        for (final c in list) (c.parentData! as _TuckedParentData).layer
      }.toList()
        ..sort())
        ...list.where(
            (c) => (c.parentData! as _TuckedParentData).layer == layer),
    ];
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final childConstraints = BoxConstraints.tightFor(width: width);
    var y = 0.0;
    var first = true;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(childConstraints, parentUsesSize: true);
      final data = child.parentData! as _TuckedParentData;
      if (!first) y -= data.overlap;
      data.offset = Offset(0, y);
      y += child.size.height;
      first = false;
    }
    size = constraints.constrain(Size(width, math.max(0, y)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _painted) {
      final data = child.parentData! as _TuckedParentData;
      context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _painted.reversed) {
      final data = child.parentData! as _TuckedParentData;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
