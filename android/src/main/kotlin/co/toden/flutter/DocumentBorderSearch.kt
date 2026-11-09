package co.toden.flutter

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * The card-border search, ported from the web SDK's useDocumentDetection.ts
 * (directional Sobel, row/column projections, findPeaks, findCardBounds) with
 * the same constants. Pure Kotlin, no Android imports, so it runs under JUnit.
 *
 * The decisive test is that ALL FOUR sides are continuous, straight,
 * high-contrast lines: a face or a hand has at best one or two, a card has
 * four. A card running out of shot has three, which is the point: its corners
 * cannot be checked, so it is not reported.
 */
internal object DocumentBorderSearch {
  // Long side over short side. A card is ~1.59, a passport page ~1.42 and a NIN
  // slip 2.00 to 2.32 (measured), so the band runs from 1.15 to 2.45.
  const val RATIO_MIN = 1.15
  const val RATIO_MAX = 2.45
  const val MIN_AREA_FRACTION = 0.1
  const val MAX_AREA_FRACTION = 0.95
  const val MIN_WIDTH_FRACTION = 0.3
  const val MIN_HEIGHT_FRACTION = 0.18
  const val BORDER_MIN_FILL = 0.55
  const val PEAK_REL_THRESHOLD = 0.32
  const val MAX_PEAKS = 6
  // How far past a side its neighbours are followed, as a share of the image,
  // and the fewest pixels worth judging (closer to the image's edge than this,
  // the corner gate refuses the corner anyway).
  const val PAST_FRACTION = 0.06
  const val PAST_MIN_PX = 3

  /** A found rectangle, in pixel rows/columns of the searched image. */
  data class Bounds(val top: Int, val bottom: Int, val left: Int, val right: Int)

  /** |d/dx| (vertical edges) and |d/dy| (horizontal edges), apart. */
  fun directionalSobel(gray: FloatArray, w: Int, h: Int): Pair<FloatArray, FloatArray> {
    val gx = FloatArray(w * h)
    val gy = FloatArray(w * h)
    for (y in 1 until h - 1) {
      for (x in 1 until w - 1) {
        val tl = gray[(y - 1) * w + (x - 1)]
        val tc = gray[(y - 1) * w + x]
        val tr = gray[(y - 1) * w + (x + 1)]
        val ml = gray[y * w + (x - 1)]
        val mr = gray[y * w + (x + 1)]
        val bl = gray[(y + 1) * w + (x - 1)]
        val bc = gray[(y + 1) * w + x]
        val br = gray[(y + 1) * w + (x + 1)]
        val sx = -tl - 2 * ml - bl + tr + 2 * mr + br
        val sy = -tl - 2 * tc - tr + bl + 2 * bc + br
        gx[y * w + x] = abs(sx)
        gy[y * w + x] = abs(sy)
      }
    }
    return gx to gy
  }

  private fun meanStd(arr: FloatArray): Pair<Double, Double> {
    var sum = 0.0
    var sumSq = 0.0
    for (v in arr) { sum += v; sumSq += v.toDouble() * v }
    val mean = sum / arr.size
    return mean to sqrt(max(0.0, sumSq / arr.size - mean * mean))
  }

  private fun smooth3(arr: DoubleArray) {
    var prev = arr[0]
    for (i in 1 until arr.size - 1) {
      val cur = arr[i]
      arr[i] = (prev + cur + arr[i + 1]) / 3
      prev = cur
    }
  }

  /** The strongest well-separated local maxima, sorted ascending. */
  fun findPeaks(proj: DoubleArray): List<Int> {
    val max = proj.maxOrNull() ?: return emptyList()
    if (max <= 0) return emptyList()
    val thresh = max * PEAK_REL_THRESHOLD
    val candidates = ArrayList<Pair<Int, Double>>()
    for (i in proj.indices) {
      val v = proj[i]
      if (v < thresh) continue
      val prev = if (i > 0) proj[i - 1] else Double.NEGATIVE_INFINITY
      val next = if (i < proj.size - 1) proj[i + 1] else Double.NEGATIVE_INFINITY
      if (v >= prev && v >= next) candidates.add(i to v)
    }
    candidates.sortByDescending { it.second }
    val chosen = ArrayList<Int>()
    for ((pos, _) in candidates) {
      if (chosen.all { abs(it - pos) >= 3 }) {
        chosen.add(pos)
        if (chosen.size >= MAX_PEAKS) break
      }
    }
    return chosen.sorted()
  }

  private fun horizontalFill(gy: FloatArray, r: Int, left: Int, right: Int, w: Int, h: Int, t: Double): Double {
    val span = right - left + 1
    if (span <= 0) return 0.0
    var best = 0.0
    for (rr in r - 1..r + 1) {
      if (rr < 0 || rr >= h) continue
      var count = 0
      for (x in left..right) if (gy[rr * w + x] > t) count++
      best = max(best, count.toDouble() / span)
    }
    return best
  }

  private fun verticalFill(gx: FloatArray, c: Int, top: Int, bottom: Int, w: Int, t: Double): Double {
    val span = bottom - top + 1
    if (span <= 0) return 0.0
    var best = 0.0
    for (cc in c - 1..c + 1) {
      if (cc < 0 || cc >= w) continue
      var count = 0
      for (y in top..bottom) if (gx[y * w + cc] > t) count++
      best = max(best, count.toDouble() / span)
    }
    return best
  }

  /** The best card-shaped rectangle with four real borders, or null. */
  /**
   * [upright] searches for a document standing upright (taller than wide): a
   * NIN slip turned upright on a phone held upright (the Dart side's
   * config/document_turn.dart). Otherwise only landscape shapes count, so a
   * door frame or a phone in shot cannot stand in for a card.
   */
  fun findCardBounds(
    gx: FloatArray, gy: FloatArray, w: Int, h: Int, upright: Boolean = false,
  ): Bounds? {
    val (mx, sxStd) = meanStd(gx)
    val (my, syStd) = meanStd(gy)
    val vThresh = mx + 0.6 * sxStd
    val hThresh = my + 0.6 * syStd

    val rowProj = DoubleArray(h)
    val colProj = DoubleArray(w)
    for (y in 0 until h) {
      var rowSum = 0.0
      for (x in 0 until w) {
        rowSum += gy[y * w + x]
        colProj[x] += gx[y * w + x].toDouble()
      }
      rowProj[y] = rowSum
    }
    smooth3(rowProj)
    smooth3(colProj)
    val hPeaks = findPeaks(rowProj)
    val vPeaks = findPeaks(colProj)
    if (hPeaks.size < 2 || vPeaks.size < 2) return null

    val minH = MIN_HEIGHT_FRACTION * h
    val minW = MIN_WIDTH_FRACTION * w
    val frameArea = (w * h).toDouble()
    var best: Bounds? = null
    var bestScore = -1.0
    for (a in hPeaks.indices) for (b in a + 1 until hPeaks.size) {
      val top = hPeaks[a]
      val bottom = hPeaks[b]
      val bh = bottom - top
      if (bh < minH) continue
      for (c in vPeaks.indices) for (d in c + 1 until vPeaks.size) {
        val left = vPeaks[c]
        val right = vPeaks[d]
        val bw = right - left
        if (bw < minW) continue
        val ratio = if (upright) bh.toDouble() / bw else bw.toDouble() / bh
        if (ratio < RATIO_MIN || ratio > RATIO_MAX) continue
        val areaFrac = bw.toDouble() * bh / frameArea
        if (areaFrac < MIN_AREA_FRACTION || areaFrac > MAX_AREA_FRACTION) continue
        val tf = horizontalFill(gy, top, left, right, w, h, hThresh)
        if (tf < BORDER_MIN_FILL) continue
        val bf = horizontalFill(gy, bottom, left, right, w, h, hThresh)
        if (bf < BORDER_MIN_FILL) continue
        val lf = verticalFill(gx, left, top, bottom, w, vThresh)
        if (lf < BORDER_MIN_FILL) continue
        val rf = verticalFill(gx, right, top, bottom, w, vThresh)
        if (rf < BORDER_MIN_FILL) continue
        // Upright, a slip too big for the picture still shows boxes printed on
        // it (its inner border, rows of its table). Their edges run on past
        // their corners, as a document's own edges never do.
        if (upright && paperRunsOn(gx, gy, left, top, right, bottom, w, h, hThresh, vThresh)) continue

        val minFill = min(min(tf, bf), min(lf, rf))
        val avgFill = (tf + bf + lf + rf) / 4
        val cx = (left + right) / 2.0 / w
        val cy = (top + bottom) / 2.0 / h
        val centreBonus = 0.15 * (1 - min(hypot(cx - 0.5, cy - 0.5) / 0.5, 1.0))
        val score = minFill * 0.6 + avgFill * 0.25 + centreBonus
        if (score > bestScore) {
          bestScore = score
          best = Bounds(top, bottom, left, right)
        }
      }
    }
    return best
  }

  /**
   * True when the paper carries on past one of the box's sides: the two edges
   * that meet that side both keep going beyond it. A document's edges stop at
   * its corners, so such a box is something printed on a document that runs
   * out of the picture, and its corners say nothing about the document's.
   *
   * A side too near the image's edge to look past is left to the corner gate,
   * which refuses a corner there anyway.
   */
  fun paperRunsOn(
    gx: FloatArray, gy: FloatArray,
    left: Int, top: Int, right: Int, bottom: Int,
    w: Int, h: Int, hThresh: Double, vThresh: Double,
  ): Boolean {
    val reachX = max(PAST_MIN_PX, Math.round(w * PAST_FRACTION).toInt())
    val reachY = max(PAST_MIN_PX, Math.round(h * PAST_FRACTION).toInt())
    // Two pixels clear of the side, so its own blur is not counted.
    fun pastRows(from: Int, to: Int): Boolean =
      to - from + 1 >= PAST_MIN_PX &&
        horizontalFill(gy, top, from, to, w, h, hThresh) >= BORDER_MIN_FILL &&
        horizontalFill(gy, bottom, from, to, w, h, hThresh) >= BORDER_MIN_FILL
    fun pastCols(from: Int, to: Int): Boolean =
      to - from + 1 >= PAST_MIN_PX &&
        verticalFill(gx, left, from, to, w, vThresh) >= BORDER_MIN_FILL &&
        verticalFill(gx, right, from, to, w, vThresh) >= BORDER_MIN_FILL
    return pastRows(max(0, left - 2 - reachX), left - 2) ||
      pastRows(right + 2, min(w - 1, right + 2 + reachX)) ||
      pastCols(max(0, top - 2 - reachY), top - 2) ||
      pastCols(bottom + 2, min(h - 1, bottom + 2 + reachY))
  }
}
