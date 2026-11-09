package co.toden.flutter

import kotlin.math.max
import kotlin.math.min

/**
 * Reading a long document turned upright on a phone held upright (a NIN slip;
 * the rule is the Dart side's config/document_turn.dart). Read upright, its
 * text runs sideways and comes back as nonsense, so the frame is read with an
 * EXTRA clockwise quarter turn on top of CameraX's own rotation.
 *
 * Pure Kotlin, so the arithmetic runs under JUnit.
 */
internal object TurnedText {
  /** Only these extra turns are meaningful; anything else reads upright. */
  fun normalise(turn: Int): Int = if (turn == 1 || turn == 2 || turn == 3) turn else 0

  /** The rotation to hand ML Kit: CameraX's [rotationDegrees] plus [turn]
   *  extra clockwise quarters. */
  fun mlKitRotation(rotationDegrees: Int, turn: Int): Int =
    ((rotationDegrees + 90 * normalise(turn)) % 360 + 360) % 360

  /**
   * Maps a box normalised (0..1) in the frame ML Kit read (the upright frame
   * turned [turn] quarters clockwise) back into the upright frame, as
   * left, top, right, bottom. A box is mapped by its two corners, which stay
   * opposite corners under a quarter turn.
   */
  fun boundsToUpright(l: Double, t: Double, r: Double, b: Double, turn: Int): DoubleArray {
    fun back(u: Double, v: Double): Pair<Double, Double> = when (normalise(turn)) {
      1 -> v to 1 - u // undo a clockwise quarter: turn the point back
      2 -> 1 - u to 1 - v
      3 -> 1 - v to u
      else -> u to v
    }
    val (x1, y1) = back(l, t)
    val (x2, y2) = back(r, b)
    return doubleArrayOf(min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
  }
}
