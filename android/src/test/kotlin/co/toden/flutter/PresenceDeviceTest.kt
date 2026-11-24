package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * Replays test/presence_seal_vectors.json (package root), shared with the RN
 * SDK's presenceDeviceVectors.test.ts, Dart's presence_device_vectors_test.dart
 * and the iOS PresenceDeviceTests.swift.
 */
class PresenceDeviceTest {
  private fun file(name: String): JSONObject {
    var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
    repeat(6) {
      val candidate = File(dir, "test/$name")
      if (candidate.isFile) return JSONObject(candidate.readText())
      dir = dir?.parentFile ?: return@repeat
    }
    throw AssertionError("$name not found above ${System.getProperty("user.dir")}")
  }

  private val doc by lazy { file("presence_seal_vectors.json") }
  private fun cases(key: String): List<JSONObject> = doc.getJSONArray(key).let { a -> (0 until a.length()).map(a::getJSONObject) }
  private fun JSONObject.longOrNull(key: String): Long? = if (isNull(key)) null else getLong(key)
  private fun JSONObject.intOrNull(key: String): Int? = if (isNull(key)) null else getInt(key)
  private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else getString(key)

  @Test
  fun usesTheSharedIntervals() {
    assertEquals(doc.getLong("refreshIntervalMillis"), PresenceDeviceRules.REFRESH_INTERVAL_MS)
    assertEquals(doc.getLong("backOffMillis"), PresenceDeviceRules.BACK_OFF_MS)
  }

  /** The format the Keystore signer produces (SHA256withECDSA, DER) is the one core verifies. */
  @Test
  fun aSharedSignatureVerifiesAndATamperedTextDoesNot() {
    val sig = doc.getJSONObject("signature")
    val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(sig.getString("publicKey"))))
    fun verifies(text: String): Boolean = Signature.getInstance("SHA256withECDSA").run {
      initVerify(key)
      update(text.toByteArray(Charsets.UTF_8))
      verify(Base64.getDecoder().decode(sig.getString("signature")))
    }
    assertTrue(verifies(sig.getString("text")))
    assertFalse(verifies(sig.getString("tamperedText")))
    // The SPKI a Keystore key's getPublicKey().encoded gives is this shape.
    assertEquals(doc.getJSONObject("key").getString("spki"), Base64.getEncoder().encodeToString(key.encoded))
  }

  /** Core's file, copied into the fixture: core's signatures verify over the texts built here. */
  @Test
  fun coreSignaturesVerifyOverTheTextsBuiltHere() {
    val c = doc.getJSONObject("core")
    val publicKey = c.getString("publicKey")
    val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(publicKey)))
    fun holds(text: String, signature: String): Boolean = Signature.getInstance("SHA256withECDSA").run {
      initVerify(key)
      update(text.toByteArray(Charsets.UTF_8))
      verify(Base64.getDecoder().decode(signature))
    }
    val reg = c.getJSONObject("registration")
    val registration = PresenceDeviceRules.registrationText(reg.getString("externalUserId"), publicKey, reg.getLong("signedAt"))
    assertEquals(reg.getString("text"), registration)
    assertTrue(holds(registration, reg.getString("signature")))
    val ref = c.getJSONObject("refresh")
    val refresh = PresenceDeviceRules.refreshText(ref.getString("deviceId"), ref.getString("externalUserId"), ref.getLong("signedAt"))
    assertEquals(ref.getString("text"), refresh)
    assertTrue(holds(refresh, ref.getString("signature")))
    val s = c.getJSONObject("seal")
    val seal = PresenceDeviceRules.sealText(s.getString("deviceId"), s.getString("externalUserId"), s.getJSONObject("observation"), s.getLong("observedAtMillis"))
    assertEquals(s.getString("text"), seal)
    assertTrue(holds(seal, s.getString("signature")))
  }

  @Test
  fun textsMatch() {
    for (c in cases("registration")) {
      assertEquals(c.getString("text"), PresenceDeviceRules.registrationText(c.getString("externalUserId"), c.getString("publicKey"), c.getLong("signedAt")))
    }
    for (c in cases("refresh")) {
      assertEquals(c.getString("text"), PresenceDeviceRules.refreshText(c.getString("deviceId"), c.getString("externalUserId"), c.getLong("signedAt")))
    }
    for (c in cases("seal")) {
      assertEquals(
        c.getString("name"),
        c.getString("text"),
        PresenceDeviceRules.sealText(c.getString("deviceId"), c.getString("externalUserId"), c.getJSONObject("observation"), c.getLong("observedAtMillis")),
      )
      assertEquals(c.getString("observedAt"), PresenceDeviceRules.isoMillis(c.getLong("observedAtMillis")))
    }
  }

  @Test
  fun rulesMatch() {
    for (c in cases("signedAt")) {
      assertEquals(c.getString("name"), c.getLong("expected"), PresenceDeviceRules.nextSignedAt(c.getLong("correctedNow"), c.longOrNull("lastSent")))
    }
    for (c in cases("clockOffset")) {
      assertEquals(c.getString("name"), c.longOrNull("expected"), PresenceDeviceRules.clockOffsetFrom(c.stringOrNull("date"), c.getLong("deviceNowMillis")))
    }
    for (c in cases("refreshAnswers")) {
      val want = PresenceDeviceRules.Refresh.valueOf(c.getString("outcome").uppercase())
      assertEquals(c.getString("name"), want, PresenceDeviceRules.refreshOutcome(c.intOrNull("status"), c.stringOrNull("code")))
    }
    for (c in cases("registrationAnswers")) {
      val want = PresenceDeviceRules.Registration.valueOf(c.getString("outcome").uppercase())
      assertEquals(c.getString("name"), want, PresenceDeviceRules.registrationOutcome(c.intOrNull("status"), c.stringOrNull("code")))
    }
    for (c in cases("refreshDue")) {
      assertEquals(
        c.getString("name"),
        c.getBoolean("due"),
        PresenceDeviceRules.refreshDue(c.getLong("nowMillis"), c.longOrNull("lastRefreshAtMillis"), c.longOrNull("backOffUntilMillis")),
      )
    }
    for (c in cases("heldWatch")) {
      val sent = c.getJSONArray("sent").let { a -> (0 until a.length()).map { JSONObject().put("day", a.getString(it)) } }
      val removed = PresenceDeviceRules.removableAfterSend(sent, c.stringOrNull("deadlineDay")).map { it.getString("day") }
      val want = c.getJSONArray("removed").let { a -> (0 until a.length()).map(a::getString) }
      assertEquals(c.getString("name"), want, removed)
    }
  }

  /** Background refresh has no Dart, so the identity check runs natively on the same cases. */
  @Test
  fun aRefreshedTokenIsCheckedAsDartChecksAProvidersAnswer() {
    val tokens = file("user_token_vectors.json")
    val now = tokens.getLong("nowMillis")
    val identity = tokens.getJSONArray("identity")
    for (i in 0 until identity.length()) {
      val v = identity.getJSONObject(i)
      val checked = PresenceUserToken.checkMinted(v.getJSONObject("body"), v.getString("actingFor"), v.getString("apiKey"), now)
      assertEquals(v.getString("name"), v.getString("expected"), if (checked == null) "user_token_mismatch" else "ok")
    }
    assertNull(PresenceUserToken.parseExpiresAt("2026-11-19T11:06:40+01:00"))
    assertNotNull(PresenceUserToken.parseExpiresAt("2026-11-19T11:06:40Z"))
    assertEquals(1795000000000L, PresenceUserToken.parseExpiresAt("2026-11-18T11:06:40.000Z"))
  }

  @Test
  fun theKeyRequestIsNeverExportableAndSignsInTheBackground() {
    val spec = PresenceDeviceKey.requestFor(strongBox = true)
    assertEquals("secp256r1", spec.curve)
    assertEquals("SHA-256", spec.digest)
    assertTrue(spec.signOnly)
    assertFalse(spec.userAuthenticationRequired)
    assertFalse(spec.unlockedDeviceRequired)
    assertTrue(spec.strongBox)
    assertFalse(PresenceDeviceKey.requestFor(strongBox = false).strongBox)
  }

  @Suppress("unused")
  private fun unused(a: JSONArray) = a
}
