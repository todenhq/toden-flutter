package co.toden.flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class Mp4AudioTrackTest {
  @Test
  fun `describes AAC-LC at 44100 Hz mono`() {
    // 5 bits object type (2), 4 bits rate index (4), 4 bits channels (1).
    val config = Mp4AudioTrack.audioSpecificConfig()
    assertArrayEquals(byteArrayOf(0x12, 0x08), config)
    val bits = ((config[0].toInt() and 0xFF) shl 8) or (config[1].toInt() and 0xFF)
    assertEquals(2, bits shr 11)
    assertEquals(4, (bits shr 7) and 0xF)
    assertEquals(1, (bits shr 3) and 0xF)
  }

  @Test
  fun `times samples from zero`() {
    assertEquals(0L, Mp4AudioTrack.ptsUsFor(0))
    assertEquals(1_000_000L, Mp4AudioTrack.ptsUsFor(44_100))
    assertEquals(23_219L, Mp4AudioTrack.ptsUsFor(1_024))
  }
}
