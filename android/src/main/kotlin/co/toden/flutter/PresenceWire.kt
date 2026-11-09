package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject

/**
 * The request body for a background flush. Apart from the geofencer so the JVM
 * tests can build it, and so the shape stays one function. The token proves the
 * report comes from the device that captured the pin; without one the server
 * counts the report at the foreground tier. Mirrors the iOS PresenceWire.swift.
 */
object PresenceWire {
  fun body(externalUserId: String, presenceToken: String?, observations: JSONArray): JSONObject {
    val body = JSONObject().put("externalUserId", externalUserId)
    if (!presenceToken.isNullOrEmpty()) body.put("presenceToken", presenceToken)
    return body.put("observations", observations)
  }
}
