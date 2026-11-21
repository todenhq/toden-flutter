import 'package:flutter/widgets.dart';

import '../liveness/selfie_review.dart';
import 'liveness_cutout.dart';

// ─── The selfie review's picture ──────────────────────────────────────────────
//
// The camera frame the selfie was cut from, drawn as the camera drew it, moved
// so the face sits in the window and made smaller only if the face would spill
// over it (liveness/selfie_review.dart). LivenessImmersiveFrame lays the same
// light blur over it round the window as the camera had. An edge the picture
// no longer reaches fades out rather than ending in a hard line. A port of the
// web SDK's ReviewView `sceneStyle`.

/// Where the picture stops short of the screen, it fades out over this.
const double kReviewSceneFade = 56;

class ReviewScene extends StatelessWidget {
  const ReviewScene({super.key, required this.scene});

  final SelfieScene scene;

  @override
  Widget build(BuildContext context) {
    // Read from the VIEW, as LivenessImmersiveFrame does, so the window here is
    // the window it draws.
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;
    return LayoutBuilder(builder: (context, constraints) {
      final frame = constraints.biggest;
      if (frame.isEmpty) return const SizedBox.shrink();
      final window = livenessCutout(frame);
      final top = (frame.height - window.height) / 2 +
          livenessWindowDrop(frame, window, insets.top);
      final at = sceneOnReview(
        Size(scene.width.toDouble(), scene.height.toDouble()),
        scene.face,
        frame,
        window,
        top,
      );
      final gaps = uncovered(at, frame);
      Widget picture = Image.memory(
        scene.jpeg,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      );
      if (gaps.left || gaps.right) {
        picture = _fade(picture, Axis.horizontal, gaps.left, gaps.right, at.width);
      }
      if (gaps.top || gaps.bottom) {
        picture = _fade(picture, Axis.vertical, gaps.top, gaps.bottom, at.height);
      }
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [Positioned.fromRect(rect: at, child: picture)],
      );
    });
  }

  Widget _fade(Widget child, Axis axis, bool start, bool end, double length) {
    final edge = length <= 0 ? 0.0 : (kReviewSceneFade / length).clamp(0.0, 0.5);
    const solid = Color(0xFF000000);
    const clear = Color(0x00000000);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [start ? clear : solid, solid, solid, end ? clear : solid],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}
