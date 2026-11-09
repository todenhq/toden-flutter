package co.toden.flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class TurnedTextTest {
  private val tol = 1e-9

  @Test
  fun addsTheExtraQuarterTurnsToCameraXsRotation() {
    assertEquals(90, TurnedText.mlKitRotation(90, 0))
    assertEquals(180, TurnedText.mlKitRotation(90, 1))
    assertEquals(0, TurnedText.mlKitRotation(90, 3))
    assertEquals(0, TurnedText.mlKitRotation(270, 1))
    // An unknown turn reads upright rather than at some arbitrary angle.
    assertEquals(90, TurnedText.mlKitRotation(90, 5))
  }

  @Test
  fun leavesAnUprightReadsBoxAlone() {
    assertArrayEquals(
      doubleArrayOf(0.1, 0.2, 0.3, 0.4),
      TurnedText.boundsToUpright(0.1, 0.2, 0.3, 0.4, 0), tol,
    )
  }

  @Test
  fun mapsABoxReadAfterOneClockwiseQuarterBack() {
    // Read frame = upright turned 90 clockwise: its top-left strip came from
    // the upright frame's bottom-left.
    assertArrayEquals(
      doubleArrayOf(0.0, 0.9, 0.1, 1.0),
      TurnedText.boundsToUpright(0.0, 0.0, 0.1, 0.1, 1), tol,
    )
  }

  @Test
  fun mapsABoxReadAfterThreeClockwiseQuartersBack() {
    // Three clockwise quarters: the read frame's top-left came from the upright
    // frame's top-right.
    assertArrayEquals(
      doubleArrayOf(0.9, 0.0, 1.0, 0.1),
      TurnedText.boundsToUpright(0.0, 0.0, 0.1, 0.1, 3), tol,
    )
  }
}
