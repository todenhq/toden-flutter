package co.toden.flutter

import org.junit.Assert.assertEquals
import org.junit.Test
import java.security.MessageDigest

class PresenceReportProofTest {
  private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

  // The vector kyc-core's report-proof.test.ts pins: every copy must agree
  // byte for byte, or the platform's proof never verifies.
  @Test
  fun `the digest matches the server vector`() {
    val text = PresenceReportProof.digestText(
      "user_123",
      "stable-1",
      "install-1",
      listOf(
        PresenceReportProof.Row("2026-10-30", 120, true, 3, false, false),
        PresenceReportProof.Row("2026-10-31", 0, false, 1, true, false, source = "foreground"),
      ),
    )
    val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
    assertEquals("14e467f5a1431e451564634466e45e7c3a62693f9bd026c9c19570c03cbf8640", hex(digest))
  }

  @Test
  fun `the request hash binds the challenge the way the server does`() {
    val sha = { b: ByteArray -> MessageDigest.getInstance("SHA-256").digest(b) }
    val challenge = "issued".toByteArray()
    val bound = sha(challenge + sha("text".toByteArray()))
    assertEquals(hex(sha(bound)), PresenceReportProof.requestHash(challenge, "text"))
  }
}
