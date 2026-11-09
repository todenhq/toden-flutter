package co.toden.flutter

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Finds an ID document's four corners in a camera frame's luma plane, so Dart
 * can refuse a capture that cuts a corner off (document_corners.dart). ML Kit
 * has no rectangle detector, so this is the web SDK's border detector ported:
 * see [DocumentBorderSearch].
 *
 * The frame is downscaled (the search needs edges, not detail, and runs four
 * times a second), rotated UPRIGHT with CameraX's `rotationDegrees`, searched,
 * and the corners returned normalised (0..1) in the upright frame, x right and
 * y down: eight numbers, x then y for top-left, top-right, bottom-right and
 * bottom-left. The rectangle is axis-aligned, so a card held at a tilt reports
 * its bounding rectangle or nothing.
 *
 * Pure Kotlin with no Android imports, so it is unit-tested on the JVM.
 */
class DocumentBorderDetector(private val shortSide: Int = 150) {

  /**
   * [upright] looks for a document standing upright rather than landscape (see
   * [DocumentBorderSearch.findCardBounds]).
   *
   * [luma] holds the frame's Y values; [rowStride] and [pixelStride] address
   * them as CameraX lays them out. Null when no document is found.
   */
  fun detect(
    luma: ByteArray,
    width: Int,
    height: Int,
    rowStride: Int = width,
    pixelStride: Int = 1,
    rotationDegrees: Int = 0,
    upright: Boolean = false,
  ): DoubleArray? {
    if (width < 4 || height < 4) return null
    val rotation = ((rotationDegrees % 360) + 360) % 360
    val turned = rotation == 90 || rotation == 270
    val uprightW = if (turned) height else width
    val uprightH = if (turned) width else height
    val scale = min(1.0, shortSide.toDouble() / min(uprightW, uprightH))
    val outW = max(4, (uprightW * scale).roundToInt())
    val outH = max(4, (uprightH * scale).roundToInt())

    // Downscale in the sensor's orientation, then turn the small image upright.
    val sensorW = if (turned) outH else outW
    val sensorH = if (turned) outW else outH
    val small = downscale(luma, width, height, rowStride, pixelStride, sensorW, sensorH)
    val gray = rotate(small, sensorW, sensorH, rotation)

    val (gx, gy) = DocumentBorderSearch.directionalSobel(gray, outW, outH)
    val b = DocumentBorderSearch.findCardBounds(gx, gy, outW, outH, upright) ?: return null
    val l = b.left.toDouble() / outW
    val r = b.right.toDouble() / outW
    val t = b.top.toDouble() / outH
    val bt = b.bottom.toDouble() / outH
    return doubleArrayOf(l, t, r, t, r, bt, l, bt)
  }

  /** Box-average of the Y plane down to [outW] x [outH]. */
  private fun downscale(
    luma: ByteArray, w: Int, h: Int, rowStride: Int, pixelStride: Int,
    outW: Int, outH: Int,
  ): FloatArray {
    val out = FloatArray(outW * outH)
    for (oy in 0 until outH) {
      val y0 = oy * h / outH
      val y1 = max(y0 + 1, (oy + 1) * h / outH)
      for (ox in 0 until outW) {
        val x0 = ox * w / outW
        val x1 = max(x0 + 1, (ox + 1) * w / outW)
        var sum = 0L
        var count = 0
        // Every second pixel each way: an average needs no more, and this runs
        // on every analysed frame.
        var y = y0
        while (y < y1) {
          var x = x0
          val row = y * rowStride
          while (x < x1) {
            val i = row + x * pixelStride
            if (i < luma.size) { sum += luma[i].toInt() and 0xFF; count++ }
            x += 2
          }
          y += 2
        }
        out[oy * outW + ox] = if (count == 0) 0f else sum.toFloat() / count
      }
    }
    return out
  }

  /** Rotates a [w] x [h] image clockwise by [rotation] degrees (0/90/180/270). */
  private fun rotate(src: FloatArray, w: Int, h: Int, rotation: Int): FloatArray {
    if (rotation == 0) return src
    val out = FloatArray(src.size)
    for (y in 0 until h) for (x in 0 until w) {
      val v = src[y * w + x]
      when (rotation) {
        90 -> out[x * h + (h - 1 - y)] = v // upright is h wide
        180 -> out[(h - 1 - y) * w + (w - 1 - x)] = v
        270 -> out[(w - 1 - x) * h + y] = v
        else -> out[y * w + x] = v
      }
    }
    return out
  }
}
