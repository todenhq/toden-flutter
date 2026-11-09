package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** The background flush's body. A port of the RN SDK's presenceToken.test.ts. */
class PresenceWireTest {
  private val days = JSONArray().put(JSONObject().put("day", "2026-11-01"))

  @Test
  fun carriesTheTokenBesideTheObservations() {
    val body = PresenceWire.body("user_1", "tok_1", days)
    assertEquals("user_1", body.getString("externalUserId"))
    assertEquals("tok_1", body.getString("presenceToken"))
    assertEquals(1, body.getJSONArray("observations").length())
  }

  @Test
  fun leavesItOutWhenThePinHasNone() {
    assertFalse(PresenceWire.body("user_1", null, days).has("presenceToken"))
    assertFalse(PresenceWire.body("user_1", "", days).has("presenceToken"))
  }
}
