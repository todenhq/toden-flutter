package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Replays the background cases of test/user_token_vectors.json (package root),
 * shared with the RN SDK's userTokenVectors.test.ts, Dart's
 * user_token_vectors_test.dart and the iOS PresenceUserTokenTests.swift.
 */
class PresenceUserTokenTest {
  private fun vectors(): JSONObject {
    // Gradle runs unit tests with the module directory (android/) as the
    // working directory; walk up until the package-root file appears.
    var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
    repeat(6) {
      val candidate = File(dir, "test/user_token_vectors.json")
      if (candidate.isFile) return JSONObject(candidate.readText())
      dir = dir?.parentFile ?: return@repeat
    }
    throw AssertionError("user_token_vectors.json not found above ${System.getProperty("user.dir")}")
  }

  @Test
  fun namesTheHeaderTheServerReads() {
    val doc = vectors()
    assertEquals(doc.getString("header"), PresenceUserToken.HEADER)
    assertEquals(doc.getInt("chunkDays"), PresenceFlush.CHUNK_DAYS)
  }

  @Test
  fun backgroundFlushMatchesTheSharedCases() {
    val doc = vectors()
    val now = doc.getLong("nowMillis")
    val cases = doc.getJSONArray("background")
    assertTrue("meaningful case set", cases.length() >= 10)
    for (i in 0 until cases.length()) {
      val v = cases.getJSONObject(i)
      val name = v.getString("name")
      val raw = v.get("token")
      var stale = false
      val inUse = raw != JSONObject.NULL
      val read = when (raw) {
        "locked" -> PresenceUserToken.Read.Locked
        is JSONObject -> {
          stale = raw.optBoolean("stale", false)
          PresenceUserToken.Read.Stored(
            PresenceUserToken.Record(
              raw.getString("externalUserId"), raw.getString("token"), raw.getLong("expiresAtMillis"), stale,
            ),
          )
        }
        else -> PresenceUserToken.Read.Missing
      }
      val days = v.getJSONArray("queue")
      val queue = JSONArray()
      for (d in 0 until days.length()) queue.put(JSONObject().put("day", days.getString(d)))
      val responses = v.getJSONArray("responses")
      val posts = mutableListOf<List<String>>()
      var remaining = (0 until days.length()).map { days.getString(it) }
      var header: String? = null
      val decision = PresenceUserToken.decide(inUse, read, "cus_123", now)
      if (decision != PresenceUserToken.Decision.Skip) {
        header = (decision as? PresenceUserToken.Decision.Use)?.token
        var answered = 0
        val result = PresenceFlush.run(queue) { chunk ->
          posts.add(chunk.map { it.getString("day") })
          val status = responses.getInt(answered++)
          if (status == 0) null else status
        }
        remaining = result.remaining.map { it.getString("day") }
        if (result.refused && header != null) stale = true
      }
      val expectedPosts = v.getJSONArray("posts")
      assertEquals("$name: post count", expectedPosts.length(), posts.size)
      for (p in 0 until expectedPosts.length()) {
        val e = expectedPosts.getJSONArray(p)
        assertEquals("$name: post $p", (0 until e.length()).map { e.getString(it) }, posts[p])
      }
      if (posts.isNotEmpty()) assertEquals("$name: header", v.opt("header").takeIf { it != JSONObject.NULL }, header)
      val expectedRemaining = v.getJSONArray("remaining")
      assertEquals("$name: remaining", (0 until expectedRemaining.length()).map { expectedRemaining.getString(it) }.sorted(), remaining.sorted())
      assertEquals("$name: stale", v.getBoolean("stale"), stale)
    }
  }

  @Test
  fun aWellFormedTokenIsTheOnlyKindKept() {
    assertTrue(PresenceUserToken.wellFormed("ut_test_" + "A".repeat(43)))
    assertFalse(PresenceUserToken.wellFormed("ut_test_short"))
    assertFalse(PresenceUserToken.wellFormed("pk_test_" + "A".repeat(43)))
  }

  @Test
  fun aRefusalMarksOnlyTheTokenThatWasSentStale() {
    val a = PresenceUserToken.Record("cus_123", "ut_test_" + "A".repeat(43), 1_795_000_000_000L, stale = false)
    val b = a.copy(token = "ut_test_" + "B".repeat(43))
    // The flush sent A; a silent push stored B while it was out: B stays good.
    assertEquals(null, PresenceUserToken.staleAfterRefusal(PresenceUserToken.Read.Stored(b), a.token))
    assertEquals(a.copy(stale = true), PresenceUserToken.staleAfterRefusal(PresenceUserToken.Read.Stored(a), a.token))
    assertEquals(null, PresenceUserToken.staleAfterRefusal(PresenceUserToken.Read.Missing, a.token))
    assertEquals(null, PresenceUserToken.staleAfterRefusal(PresenceUserToken.Read.Locked, a.token))
  }

  @Test
  fun theStoredRecordRoundTrips() {
    val record = PresenceUserToken.Record("cus_123", "ut_test_" + "A".repeat(43), 1_795_000_000_000L, stale = true)
    assertEquals(record, PresenceUserToken.decode(PresenceUserToken.encode(record)))
  }
}

/** The HMAC presenceToken's one-time move out of the backed-up prefs (R65). */
class PresenceHmacTokenTest {
  private val kept = PresenceHmacToken.Stored.Kept("u", "k")

  @Test
  fun aNoBackupCopyForThisUserIsUsed() {
    assertEquals(PresenceHmacToken.Step.Use("k"), PresenceHmacToken.step(null, kept, "u"))
    assertEquals(PresenceHmacToken.Step.Use("k"), PresenceHmacToken.step("d", kept, "u"))
    assertTrue(PresenceHmacToken.has(kept, "u"))
  }

  @Test
  fun aPrefsCopyIsMovedOnce() {
    assertEquals(PresenceHmacToken.Step.MoveFromDefaults("d"), PresenceHmacToken.step("d", PresenceHmacToken.Stored.Missing, "u"))
    assertEquals(PresenceHmacToken.Step.MoveFromDefaults("d"), PresenceHmacToken.step("d", PresenceHmacToken.Stored.Kept("other", "k"), "u"))
  }

  @Test
  fun unreadableStorageHoldsTheFlushUnlessAnOldCopyRemains() {
    assertEquals(PresenceHmacToken.Step.Held, PresenceHmacToken.step(null, PresenceHmacToken.Stored.Locked, "u"))
    assertEquals(PresenceHmacToken.Step.Use("d"), PresenceHmacToken.step("d", PresenceHmacToken.Stored.Locked, "u"))
  }

  @Test
  fun noTokenAnywhereSendsNone() {
    assertEquals(PresenceHmacToken.Step.Use(null), PresenceHmacToken.step(null, PresenceHmacToken.Stored.Missing, "u"))
    assertFalse(PresenceHmacToken.has(PresenceHmacToken.Stored.Kept("other", "k"), "u"))
  }
}
