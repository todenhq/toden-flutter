package co.toden.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * The Android corner detector on synthetic frames. The upright frame is a
 * portrait 360 x 640 (the analysis stream's 9:16) unless a test says otherwise.
 */
class DocumentBorderDetectorTest {
  private val w = 360
  private val h = 640
  private val dark = 30
  private val bright = 220

  /** An upright frame: [card] pixels bright, the rest dark with a little noise. */
  private fun upright(card: (Double, Double) -> Boolean, seed: Int = 7): IntArray {
    val rnd = Random(seed)
    return IntArray(w * h) { i ->
      val x = (i % w + 0.5) / w
      val y = (i / w + 0.5) / h
      (if (card(x, y)) bright else dark) + rnd.nextInt(-6, 7)
    }
  }

  private fun rect(l: Double, t: Double, r: Double, b: Double) =
    { x: Double, y: Double -> x in l..r && y in t..b }

  private fun bytes(px: IntArray) = ByteArray(px.size) { px[it].coerceIn(0, 255).toByte() }

  private fun assertQuad(q: DoubleArray?, l: Double, t: Double, r: Double, b: Double) {
    assertNotNull("expected a document", q)
    val tol = 0.02
    assertEquals(l, q!![0], tol); assertEquals(t, q[1], tol)
    assertEquals(r, q[2], tol); assertEquals(t, q[3], tol)
    assertEquals(r, q[4], tol); assertEquals(b, q[5], tol)
    assertEquals(l, q[6], tol); assertEquals(b, q[7], tol)
  }

  @Test
  fun findsABrightCardOnADarkBackground() {
    val q = DocumentBorderDetector().detect(bytes(upright(rect(0.1, 0.35, 0.9, 0.62))), w, h)
    assertQuad(q, 0.1, 0.35, 0.9, 0.62)
  }

  @Test
  fun reportsNothingForACardRunningOffTheBottomEdge() {
    // Three borders only: its bottom corners are out of shot, which is the
    // passport-with-the-MRZ-cut case the corners rule exists for.
    val q = DocumentBorderDetector().detect(bytes(upright(rect(0.1, 0.62, 0.9, 1.1))), w, h)
    assertNull(q)
  }

  @Test
  fun findsANinSlipStandingUprightWhenAskedTo() {
    // A slip turned upright on a phone held upright: 180 x 371 px, 2.06 long.
    val frame = bytes(upright(rect(0.25, 0.15, 0.75, 0.73)))
    assertQuad(
      DocumentBorderDetector().detect(frame, w, h, upright = true),
      0.25, 0.15, 0.75, 0.73,
    )
  }

  @Test
  fun aPortraitShapeIsNotACardUnlessAnUprightDocumentIsExpected() {
    val frame = bytes(upright(rect(0.25, 0.15, 0.75, 0.73)))
    assertNull(DocumentBorderDetector().detect(frame, w, h))
  }

  @Test
  fun reportsNothingWithoutACard() {
    assertNull(DocumentBorderDetector().detect(bytes(upright({ _, _ -> false })), w, h))
  }

  @Test
  fun reportsNothingForAPortraitShape() {
    // A face crop is square to portrait, never a landscape card.
    val q = DocumentBorderDetector().detect(bytes(upright(rect(0.25, 0.3, 0.75, 0.7))), w, h)
    assertNull(q)
  }

  @Test
  fun readsTheSensorFrameUprightWhenRotated() {
    // The sensor delivers 640 x 360 landscape; CameraX says turn it 90°
    // clockwise. sensor(x, y) is upright(359 - y, x).
    val up = upright(rect(0.1, 0.35, 0.9, 0.62))
    val sw = h
    val sh = w
    val sensor = IntArray(sw * sh) { i ->
      val x = i % sw
      val y = i / sw
      up[x * w + (w - 1 - y)]
    }
    val q = DocumentBorderDetector().detect(bytes(sensor), sw, sh, rotationDegrees = 90)
    assertQuad(q, 0.1, 0.35, 0.9, 0.62)
  }

  @Test
  fun honoursRowAndPixelStrides() {
    val up = upright(rect(0.1, 0.35, 0.9, 0.62))
    val rowStride = w * 2 + 32
    val padded = ByteArray(rowStride * h)
    for (y in 0 until h) for (x in 0 until w) {
      padded[y * rowStride + x * 2] = up[y * w + x].coerceIn(0, 255).toByte()
    }
    val q = DocumentBorderDetector().detect(padded, w, h, rowStride, pixelStride = 2)
    assertQuad(q, 0.1, 0.35, 0.9, 0.62)
  }

  @Test
  fun readsAnUprightSlipFromASensorTurned270() {
    // Some phones mount the back sensor the other way: CameraX says 270°.
    // sensor(x, y) is upright(y, 639 - x).
    val up = upright(rect(0.25, 0.15, 0.75, 0.73))
    val sw = h
    val sh = w
    val sensor = IntArray(sw * sh) { i ->
      val x = i % sw
      val y = i / sw
      up[(sw - 1 - x) * w + y]
    }
    val q = DocumentBorderDetector().detect(bytes(sensor), sw, sh, rotationDegrees = 270, upright = true)
    assertQuad(q, 0.25, 0.15, 0.75, 0.73)
  }

  /**
   * A NIN slip as it really looks, upright in a 720 x 1280 frame: pale paper
   * at (l,t)..(r,b) pixels (which may run past the frame), a printed inner
   * border and blocks of print.
   */
  private fun printedSlip(l: Int, t: Int, r: Int, b: Int, border: Double): ByteArray {
    val fw = 720; val fh = 1280
    val px = ByteArray(fw * fh) { 60 }
    fun set(x: Int, y: Int, v: Int) { if (x in 0 until fw && y in 0 until fh) px[y * fw + x] = v.toByte() }
    for (y in t until b) for (x in l until r) set(x, y, 225)
    val m = ((r - l) * border).toInt()
    for (x in l + m until r - m) for (d in 0..2) { set(x, t + m + d, 40); set(x, b - m - d, 40) }
    for (y in t + m until b - m) for (d in 0..2) { set(l + m + d, y, 40); set(r - m - d, y, 40) }
    var x = l + m + 20
    while (x < r - m - 20) {
      var y = t + m + 20
      while (y < b - m - 20) { for (yy in y until y + 6) for (xx in x until x + 8) set(xx, yy, 50); y += 10 }
      x += 22
    }
    return px
  }

  @Test
  fun findsAPrintedSlipThatIsWhollyInView() {
    val slipH = 1000; val slipW = (slipH / 2.07).toInt()
    val l = (720 - slipW) / 2; val t = (1280 - slipH) / 2
    val q = DocumentBorderDetector().detect(printedSlip(l, t, l + slipW, t + slipH, 0.06), 720, 1280, upright = true)
    assertQuad(q, l / 720.0, t / 1280.0, (l + slipW) / 720.0, (t + slipH) / 1280.0)
  }

  @Test
  fun doesNotTakeThePrintedBorderOfASlipRunningOffTheFrame() {
    // The paper's right side is just past the frame; its printed border is not.
    // The border's box used to be found (0.33 to 0.85 across), wholly inside
    // the 0.09 to 0.91 an upright Galaxy S24 shows, so the slip passed the
    // corner check with its edge off the screen.
    val slipH = 1000; val slipW = (slipH / 2.07).toInt()
    val l = 238; val t = (1280 - slipH) / 2
    assertTrue(l + slipW > 720)
    val q = DocumentBorderDetector().detect(printedSlip(l, t, l + slipW, t + slipH, 0.1), 720, 1280, upright = true)
    if (q != null) assertTrue("found right ${q[2]}", q[2] > 0.91)
  }

  @Test
  fun findsNothingInsideASlipTooBigForTheFrame() {
    // Held so close the paper runs past every edge: only its print is in view,
    // and a box of that print used to pass for the slip.
    val slipH = 1500; val slipW = (slipH / 2.07).toInt()
    for (dx in listOf(0, 60, 120, 180)) {
      val l = (720 - slipW) / 2 + dx; val t = (1280 - slipH) / 2
      for (border in listOf(0.06, 0.1)) {
        val q = DocumentBorderDetector().detect(printedSlip(l, t, l + slipW, t + slipH, border), 720, 1280, upright = true)
        assertNull("dx $dx border $border", q)
      }
    }
  }
}
