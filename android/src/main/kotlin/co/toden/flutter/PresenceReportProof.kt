package co.toden.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Proving a background presence report: which phone is reporting, and Play
 * Integrity's proof over these exact contents. The Dart reporter's twin
 * (presence_report_proof.dart). Best-effort: what cannot be proved is left off
 * and the report still goes.
 *
 * [digestText] is the wire contract shared with kyc-core and every SDK; all
 * copies pin one test vector, so change them in the same commit.
 *
 * Always called off the main thread: the flush already does network I/O.
 */
object PresenceReportProof {
  data class Row(
    val day: String,
    val dwellMinutes: Int,
    val nightPresent: Boolean,
    val samples: Int,
    val mockLocation: Boolean,
    val emulator: Boolean,
    val source: String = "geofence",
  )

  /** The whole step's bound: a receiver has about ten seconds to live. */
  private const val BUDGET_MS = 5000L
  private var playIntegrity: PlayIntegrity? = null

  fun digestText(externalUserId: String, stableId: String?, deviceId: String?, rows: List<Row>): String {
    val flag = { v: Boolean -> if (v) 1 else 0 }
    val lines = mutableListOf("toden-presence-report-v1", externalUserId, stableId ?: "", deviceId ?: "")
    rows.mapTo(lines) { o ->
      listOf(o.day, o.source, o.dwellMinutes, flag(o.nightPresent), o.samples, flag(o.mockLocation), flag(o.emulator))
        .joinToString("|")
    }
    return lines.joinToString("\n")
  }

  private fun sha256(vararg parts: ByteArray): ByteArray {
    val md = MessageDigest.getInstance("SHA-256")
    parts.forEach(md::update)
    return md.digest()
  }

  /** Lowercase hex SHA-256(SHA-256(challenge || SHA-256(text))). */
  fun requestHash(challenge: ByteArray, digestText: String): String {
    val bound = sha256(challenge, sha256(digestText.toByteArray(Charsets.UTF_8)))
    return sha256(bound).joinToString("") { "%02x".format(it) }
  }

  fun addTo(body: JSONObject, context: Context, config: PresenceStore.Config, observations: JSONArray) {
    val stableId = DeviceIntelHandler.androidId(context) ?: return
    body.put("device", JSONObject().put("stableId", stableId))
    val project = config.playIntegrityProject?.toLongOrNull() ?: return
    try {
      val text = digestText(config.externalUserId, stableId, null, rowsOf(observations))
      val challenge = fetchChallenge(config) ?: return
      val bytes = Base64.decode(challenge.getString("challenge"), Base64.DEFAULT)
      val token = token(context, project, requestHash(bytes, text)) ?: return
      body.put(
        "attestation",
        JSONObject()
          .put("platform", "android")
          .put("kind", "play_integrity")
          .put("challengeId", challenge.getString("challengeId"))
          .put("token", token),
      )
    } catch (_: Exception) {
      // The report goes without proof, and a proven one can replace it.
    }
  }

  private fun rowsOf(observations: JSONArray): List<Row> = (0 until observations.length()).map { i ->
    val o = observations.getJSONObject(i)
    val integrity = o.optJSONObject("integrity")
    Row(
      day = o.getString("day"),
      dwellMinutes = o.getInt("dwellMinutes"),
      nightPresent = o.getBoolean("nightPresent"),
      samples = o.getInt("samples"),
      mockLocation = integrity?.optBoolean("mockLocation") == true,
      emulator = integrity?.optBoolean("emulator") == true,
      source = o.getString("source"),
    )
  }

  private fun fetchChallenge(config: PresenceStore.Config): JSONObject? {
    var connection: HttpURLConnection? = null
    try {
      connection = URL("${config.baseUrl}/api/v1/device/challenge").openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.connectTimeout = 2000
      connection.readTimeout = 2000
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.apiKey}")
      OutputStreamWriter(connection.outputStream).use { it.write("""{"platform":"android"}""") }
      if (connection.responseCode !in 200..299) return null
      return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
    } catch (_: Exception) {
      return null
    } finally {
      connection?.disconnect()
    }
  }

  private fun token(context: Context, project: Long, hash: String): String? {
    val latch = CountDownLatch(1)
    val out = AtomicReference<String?>()
    Handler(Looper.getMainLooper()).post {
      val client = playIntegrity ?: PlayIntegrity(context.applicationContext).also { playIntegrity = it }
      client.token(project, hash) { token ->
        out.set(token)
        latch.countDown()
      }
    }
    latch.await(BUDGET_MS, TimeUnit.MILLISECONDS)
    return out.get()
  }
}
