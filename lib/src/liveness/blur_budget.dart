// ─── Can this phone afford the blur? ─────────────────────────────────────────
//
// The full-screen liveness camera blurs the live feed everywhere but the face
// window. A blur over a moving camera texture is redrawn on every frame, and
// on a slow phone it takes the frame budget the face detector also needs: the
// preview stutters and gestures are missed. So the screen watches how long its
// frames take to draw and, when too many are slow, gives the blur up for a
// flat tint. Once given up it stays given up: a screen that switched back and
// forth would be worse than either.
//
// It must take a SUSTAINED fall behind to give up. On an iPhone 16 Pro Max
// (2026-11-18) one burst of 27 slow frames in 1,680, as the camera started,
// ended the blur for the whole run and left the heavy flat tint: one window
// after a 30-frame warm-up (a quarter of a second at 120 Hz) was enough. Now
// the warm-up is longer and two windows in a row must be slow.
//
// And it judges only while the camera is simply live (lining up and the
// gestures). Taking the photo stalls the screen for about a second, which is
// two windows at 120 Hz: on the same iPhone that ended the blur just before
// the selfie, both times it was measured. Frames drawn then are not counted.

/// A frame drawn slower than this has missed a 60 Hz refresh.
const Duration kBlurSlowFrame = Duration(milliseconds: 18);

/// How many frames are judged at a time.
const int kBlurWindowFrames = 60;

/// The share of slow frames in one window that ends the blur.
const double kBlurSlowShare = 0.4;

/// The first frames after the camera opens are always slow (the texture and
/// the shaders are being set up) and say nothing about the phone: about
/// one and a half seconds at 120 Hz, three at 60.
const int kBlurWarmupFrames = 180;

/// How many slow windows in a row end the blur: a burst is not a slow phone.
const int kBlurSlowWindows = 2;

/// Feed the draw time of each frame; [affordable] turns false, for good, once
/// a whole window had too many slow ones.
class BlurBudget {
  int _seen = 0;
  int _inWindow = 0;
  int _slow = 0;
  int _slowWindows = 0;
  bool _affordable = true;

  bool get affordable => _affordable;

  /// A stretch whose frames say nothing about the phone (the photo being
  /// taken): the window in progress and the run of slow windows are dropped.
  void pause() {
    _inWindow = 0;
    _slow = 0;
    _slowWindows = 0;
  }

  /// Returns true when this frame is the one that ended the blur.
  bool add(Duration drawTime) {
    if (!_affordable) return false;
    _seen++;
    if (_seen <= kBlurWarmupFrames) return false;
    _inWindow++;
    if (drawTime > kBlurSlowFrame) _slow++;
    if (_inWindow < kBlurWindowFrames) return false;
    final tooSlow = _slow / _inWindow >= kBlurSlowShare;
    _inWindow = 0;
    _slow = 0;
    _slowWindows = tooSlow ? _slowWindows + 1 : 0;
    if (_slowWindows < kBlurSlowWindows) return false;
    _affordable = false;
    return true;
  }
}
