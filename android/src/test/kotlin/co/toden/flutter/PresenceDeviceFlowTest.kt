package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/**
 * The device record, the registration step, the seals at post time and the
 * flush's sent and dropped days. The Keystore is replaced with a software
 * P-256 key: what is checked is what gets signed and posted.
 */
class PresenceDeviceFlowTest {
  private val token = "hmac-token-1"

  @Test
  fun theRecordRoundTripsWithEveryField() {
    val r = PresenceDeviceRecord(
      "cus_123", "alias", "spki", "strongbox", "upd_1",
      refusedFor = null, lastSignedAt = 5L, lastRefreshAt = 6L, backOffUntil = 7L, clockOffset = -300000L,
      limitUntil = 8L, registeredFor = "digest",
    )
    assertEquals(r, PresenceDeviceRecords.decode(PresenceDeviceRecords.encode(r)))
    val bare = PresenceDeviceRecord("cus_123", refusedFor = PresenceDeviceRecords.tokenDigest(token))
    assertEquals(bare, PresenceDeviceRecords.decode(PresenceDeviceRecords.encode(bare)))
    assertNull(PresenceDeviceRecords.decode("not json"))
  }

  @Test
  fun theRefusalMarkIsADigestNeverTheToken() {
    val digest = PresenceDeviceRecords.tokenDigest(token)
    assertEquals(64, digest.length)
    assertFalse(PresenceDeviceRecords.encode(PresenceDeviceRecord("cus_123", refusedFor = digest)).contains(token))
  }

  @Test
  fun registrationSteps() {
    val keyed = PresenceDeviceRecord("cus_123", "alias", "spki", "tee")
    assertTrue(PresenceDeviceRecords.registrationStep(null, "cus_123", token) is PresenceDeviceRecords.Step.NewKey)
    val registered = keyed.copy(deviceId = "upd_1", registeredFor = PresenceDeviceRecords.tokenDigest(token))
    assertEquals(PresenceDeviceRecords.Step.Registered, PresenceDeviceRecords.registrationStep(registered, "cus_123", token))
    // A device serves only the verification whose token registered it: a new
    // verification's token needs a new key and a new registration.
    assertEquals(PresenceDeviceRecords.Step.NewKey("alias"), PresenceDeviceRecords.registrationStep(registered, "cus_123", "hmac-token-2"))
    assertEquals(PresenceDeviceRecords.Step.NewKey("alias"), PresenceDeviceRecords.registrationStep(keyed.copy(deviceId = "upd_1"), "cus_123", token))
    assertEquals(PresenceDeviceRecords.Step.Reuse(keyed), PresenceDeviceRecords.registrationStep(keyed, "cus_123", token))
    // Another user's key is deleted before a new one is made.
    assertEquals(PresenceDeviceRecords.Step.NewKey("alias"), PresenceDeviceRecords.registrationStep(keyed, "cus_other", token))
    val refused = PresenceDeviceRecord("cus_123", refusedFor = PresenceDeviceRecords.tokenDigest(token))
    assertEquals(PresenceDeviceRecords.Step.Refused, PresenceDeviceRecords.registrationStep(refused, "cus_123", token))
    // A new verification's token may try again.
    assertEquals(PresenceDeviceRecords.Step.NewKey(null), PresenceDeviceRecords.registrationStep(refused, "cus_123", "hmac-token-2"))
  }

  @Test
  fun anAnswerWritesBackOnlyOverTheDeviceItWasSentFor() {
    val sent = PresenceDeviceRecord("cus_123", "alias", "spki", "tee", "upd_1", lastSignedAt = 5L)
    assertTrue(PresenceDeviceRecords.stillHeld(sent, sent.copy(lastSignedAt = 6L)))
    // A logout, a deletion or a new key while the request was out.
    assertFalse(PresenceDeviceRecords.stillHeld(sent, null))
    assertFalse(PresenceDeviceRecords.stillHeld(sent, sent.copy(alias = "alias-2")))
    assertFalse(PresenceDeviceRecords.stillHeld(sent, sent.copy(deviceId = "upd_2")))
    assertFalse(PresenceDeviceRecords.stillHeld(sent, sent.copy(externalUserId = "cus_other")))
  }

  private fun wire(day: String, emulator: Boolean = false) = JSONObject()
    .put("day", day).put("source", "geofence").put("dwellMinutes", 610).put("nightPresent", true).put("samples", 14)
    .apply { if (emulator) put("integrity", JSONObject().put("emulator", true)) }

  @Test
  fun sealsSignThePostedRowAndSkipWhatCannotBeSigned() {
    val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    val sign = { text: String ->
      Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run {
        initSign(pair.private); update(text.toByteArray()); sign()
      })
    }
    val queued = listOf(
      JSONObject().put("day", "2026-11-20").put("observedAtMillis", 1795000000000L),
      // Queued before 4.5.0: no observedAt, so no seal, and still posted.
      JSONObject().put("day", "2026-11-21"),
      JSONObject().put("day", "2026-11-22").put("observedAtMillis", 1795100000000L),
    )
    val observations = JSONArray().put(wire("2026-11-20", emulator = true)).put(wire("2026-11-21")).put(wire("2026-11-22"))
    assertTrue(PresenceSeal.apply(queued, observations, "upd_1", "cus_123", sign))

    val first = observations.getJSONObject(0)
    val seal = first.getJSONObject("seal")
    assertEquals("2026-11-18T11:06:40.000Z", seal.getString("observedAt"))
    val text = "toden-presence-seal-v1\nupd_1\ncus_123\n2026-11-20|geofence|610|1|14|0|1\n1795000000000"
    val verified = Signature.getInstance("SHA256withECDSA").run {
      initVerify(pair.public); update(text.toByteArray()); verify(Base64.getDecoder().decode(seal.getString("signature")))
    }
    assertTrue("the seal covers the row as posted, emulator flag included", verified)
    assertFalse(observations.getJSONObject(1).has("seal"))
    assertTrue(observations.getJSONObject(2).has("seal"))
    // The wire row itself is untouched apart from the seal.
    assertEquals(setOf("day", "source", "dwellMinutes", "nightPresent", "samples", "integrity", "seal"), first.keys().asSequence().toSet())
  }

  @Test
  fun aKeyThatCannotSignLeavesEveryEntryUnsealed() {
    val queued = listOf(JSONObject().put("day", "2026-11-20").put("observedAtMillis", 1L))
    val observations = JSONArray().put(wire("2026-11-20"))
    assertFalse(PresenceSeal.apply(queued, observations, "upd_1", "cus_123") { null })
    assertFalse(observations.getJSONObject(0).has("seal"))
  }

  private fun queue(vararg days: String) = JSONArray().apply { days.forEach { put(JSONObject().put("day", it)) } }

  @Test
  fun theFlushReportsWhatWasSentAndWhatWasDropped() {
    val days = (1..40).map { "2026-10-%02d".format(((it - 1) % 31) + 1) + if (it > 31) "x" else "" }
    val answers = ArrayDeque(listOf(200, 400))
    val result = PresenceFlush.run(queue(*days.toTypedArray())) { answers.removeFirst() }
    assertEquals(31, result.sent.size)
    assertEquals(9, result.dropped.size)
    assertTrue(result.remaining.isEmpty())
    assertFalse(result.refused)
  }

  @Test
  fun aHeldWatchKeepsDaysAfterItsDeadline() {
    val result = PresenceFlush.run(queue("2026-11-19", "2026-11-20", "2026-11-21")) { 201 }
    val removed = PresenceDeviceRules.removableAfterSend(result.sent, "2026-11-20").map { it.getString("day") }
    assertEquals(listOf("2026-11-19", "2026-11-20"), removed)
    assertEquals(3, PresenceDeviceRules.removableAfterSend(result.sent, null).size)
  }

  @Test
  fun aRefusalKeepsTheRestQueued() {
    val answers = ArrayDeque(listOf(201, 403))
    val days = (1..40).map { "2026-%02d-%02d".format(if (it <= 31) 10 else 11, ((it - 1) % 31) + 1) }
    val result = PresenceFlush.run(queue(*days.toTypedArray())) { answers.removeFirst() }
    assertEquals(31, result.sent.size)
    assertEquals(9, result.remaining.size)
    assertTrue(result.refused)
    assertTrue(result.dropped.isEmpty())
  }
}
