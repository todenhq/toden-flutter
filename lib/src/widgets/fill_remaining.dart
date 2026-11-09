import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The height of the scrolling body a [StickyActions] holds, for
/// [FillRemainingColumn] to fill. Absent outside one.
class FillViewportScope extends InheritedWidget {
  const FillViewportScope({super.key, required this.height, required super.child});

  final double height;

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FillViewportScope>()?.height;

  @override
  bool updateShouldNotify(FillViewportScope old) => old.height != height;
}

/// A column whose [flexIndex] child (the map, or the Street View panorama)
/// takes whatever height the rest leaves in the step's body, and never less
/// than [minFlexHeight]. On a tall phone the map runs down to the Continue
/// button instead of leaving an empty band above it; on a short one it keeps
/// its usual height and the body scrolls, as before.
///
/// A custom layout rather than Column + Expanded because the body sits inside
/// a scroll view (unbounded height), and the usual workaround (IntrinsicHeight)
/// asks the map for intrinsic sizes, which a LayoutBuilder or a platform view
/// inside it cannot give. Here the other children are laid out first, then
/// the map gets the rest: no intrinsics. Children stretch to the full width.
class FillRemainingColumn extends MultiChildRenderObjectWidget {
  const FillRemainingColumn({
    super.key,
    required super.children,
    required this.flexIndex,
    required this.minFlexHeight,
  });

  final int flexIndex;
  final double minFlexHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFillRemainingColumn(
        flexIndex: flexIndex,
        minFlexHeight: minFlexHeight,
        viewportHeight: FillViewportScope.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderFillRemainingColumn renderObject) {
    renderObject
      ..flexIndex = flexIndex
      ..minFlexHeight = minFlexHeight
      ..viewportHeight = FillViewportScope.of(context);
  }
}

class _FillParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFillRemainingColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillParentData> {
  RenderFillRemainingColumn({
    required int flexIndex,
    required double minFlexHeight,
    required double? viewportHeight,
  })  : _flexIndex = flexIndex,
        _minFlexHeight = minFlexHeight,
        _viewportHeight = viewportHeight;

  int _flexIndex;
  set flexIndex(int v) {
    if (v == _flexIndex) return;
    _flexIndex = v;
    markNeedsLayout();
  }

  double _minFlexHeight;
  set minFlexHeight(double v) {
    if (v == _minFlexHeight) return;
    _minFlexHeight = v;
    markNeedsLayout();
  }

  double? _viewportHeight;
  set viewportHeight(double? v) {
    if (v == _viewportHeight) return;
    _viewportHeight = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillParentData) child.parentData = _FillParentData();
  }

  /// The flex child's height, given the others' total.
  static double flexHeightFor({
    required double? viewport,
    required double others,
    required double minimum,
  }) =>
      viewport == null || !viewport.isFinite ? minimum : math.max(minimum, viewport - others);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final stretch = BoxConstraints.tightFor(width: width);
    var others = 0.0;
    RenderBox? flex;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      if (index == _flexIndex) {
        flex = child;
      } else {
        child.layout(stretch, parentUsesSize: true);
        others += child.size.height;
      }
      child = childAfter(child);
      index++;
    }
    final flexHeight = flexHeightFor(viewport: _viewportHeight, others: others, minimum: _minFlexHeight);
    flex?.layout(BoxConstraints.tightFor(width: width, height: flexHeight), parentUsesSize: true);

    var y = 0.0;
    child = firstChild;
    while (child != null) {
      (child.parentData! as _FillParentData).offset = Offset(0, y);
      y += child.size.height;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
