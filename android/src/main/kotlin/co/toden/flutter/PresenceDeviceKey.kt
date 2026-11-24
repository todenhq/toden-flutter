package co.toden.flutter

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.UUID

/**
 * The presence device's P-256 key in the Android Keystore (user token design
 * rev 4, section 14): StrongBox when the phone has it, else the TEE. The
 * private key never leaves the Keystore and cannot be exported. No user
 * authentication and no unlocked-device requirement, so the background flush
 * can sign while the phone sits locked in a pocket.
 *
 * Below Android 6 there is no Keystore EC key: [create] answers null and
 * presence runs as before, with no refresh and no seals.
 */
object PresenceDeviceKey {
  private const val KEYSTORE = "AndroidKeyStore"
  private const val ALIAS_PREFIX = "co.toden.flutter.presence.device."

  /** What is asked of the Keystore, as a value the JVM tests can read. */
  data class KeyRequest(
    val curve: String,
    val digest: String,
    val signOnly: Boolean,
    val userAuthenticationRequired: Boolean,
    val unlockedDeviceRequired: Boolean,
    val strongBox: Boolean,
  )

  fun requestFor(strongBox: Boolean) = KeyRequest(
    curve = "secp256r1",
    digest = "SHA-256",
    signOnly = true,
    userAuthenticationRequired = false,
    unlockedDeviceRequired = false,
    strongBox = strongBox,
  )

  data class Created(val alias: String, val publicKey: String, val keyStorage: String)

  /** A new key under a new alias (one key, one registration), or null. */
  fun create(): Created? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
    val alias = ALIAS_PREFIX + UUID.randomUUID().toString()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      try {
        return generate(alias, requestFor(strongBox = true), "strongbox")
      } catch (_: StrongBoxUnavailableException) {
        // No StrongBox on this phone: the TEE below.
      } catch (_: Exception) {
        delete(alias)
      }
    }
    return try {
      generate(alias, requestFor(strongBox = false), "tee")
    } catch (_: Exception) {
      delete(alias)
      null
    }
  }

  private fun generate(alias: String, request: KeyRequest, storage: String): Created {
    val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
      .setAlgorithmParameterSpec(ECGenParameterSpec(request.curve))
      .setDigests(KeyProperties.DIGEST_SHA256)
      .setUserAuthenticationRequired(request.userAuthenticationRequired)
    if (request.strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) builder.setIsStrongBoxBacked(true)
    val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
    generator.initialize(builder.build())
    val pair = generator.generateKeyPair()
    // X.509 SubjectPublicKeyInfo, DER: what core reads.
    return Created(alias, Base64.encodeToString(pair.public.encoded, Base64.NO_WRAP), storage)
  }

  /** ECDSA-SHA256 over [text], base64 DER, or null when the key is gone. */
  fun sign(alias: String, text: String): String? = try {
    val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
    val key = store.getKey(alias, null) as? PrivateKey
    if (key == null) {
      null
    } else {
      val signer = Signature.getInstance("SHA256withECDSA")
      signer.initSign(key)
      signer.update(text.toByteArray(Charsets.UTF_8))
      Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
    }
  } catch (_: Exception) {
    null
  }

  fun delete(alias: String) {
    try {
      KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(alias)
    } catch (_: Exception) {
      // Nothing to delete.
    }
  }
}
