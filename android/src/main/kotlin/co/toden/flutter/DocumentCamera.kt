package co.toden.flutter

import android.content.Context
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

/**
 * Owns the Android camera for the **document** step, replacing the Flutter
 * camera plugin on this screen (iOS keeps the plugin — its preview is stable).
 *
 * One CameraX session, three use cases — **Preview + ImageAnalysis +
 * ImageCapture** — a combination supported down to LEGACY devices. The plugin
 * path instead needed Preview + ImageAnalysis + *VideoCapture*, which exceeds
 * the use-case cap on many phones: CameraX then downgrades stream resolutions
 * (the soft preview), and `takePicture` has to tear the recording down and
 * reconfigure the surface (the stutter, and the sideways flash the Dart side
 * had to hide behind a cover).
 *
 * Here the side clip is encoded by [DocumentVideoRecorder] off the SAME analysis
 * frames ML Kit reads — the [LivenessRecorder] trick — so no VideoCapture use
 * case is needed and a still is just `ImageCapture.takePicture` with nothing to
 * tear down.
 *
 * Preview renders into a Flutter [TextureRegistry.SurfaceTextureEntry] already
 * upright and display-oriented, so Dart shows it with a plain `Texture` at a
 * fixed portrait aspect: the accelerometer-driven preview rotation the plugin
 * exhibits cannot happen here, and no warmup cover is needed.
 *
 * Auto-capture runs natively too — ML Kit text recognition on the analysis
 * frames, streaming recognized lines to Dart (which keeps every framing/MRZ
 * decision) — so no camera frame is copied over the method channel per tick.
 */
class DocumentCamera(
  private val context: Context,
  private val textures: TextureRegistry,
  /** Per analysed frame: `lines` (recognized text), optional `bounds`
   *  (normalised union of the text blocks), `quad` (the document's corners,
   *  or absent when none were found) and `frameW`/`frameH`. */
  private val onText: (Map<String, Any>) -> Unit,
  /** The scan's camera by default. With analysis off (the in-SDK photo
   *  camera) no ImageAnalysis is bound: no text, no corners, no clip. */
  private val mode: DocumentCameraMode = DocumentCameraMode(),
) : LifecycleOwner {

  private val tag = "KycDocumentCamera"

  // Minimal lifecycle we drive ourselves (CameraX binds to it).
  private val lifecycleRegistry = LifecycleRegistry(this)
  override val lifecycle: Lifecycle get() = lifecycleRegistry

  private val analysisExecutor = Executors.newSingleThreadExecutor()
  private val video = DocumentVideoRecorder(context)
  private var cameraProvider: ProcessCameraProvider? = null
  private var imageCapture: ImageCapture? = null
  private var camera: androidx.camera.core.Camera? = null

  private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
  val textureId: Long get() = textureEntry?.id() ?: -1

  // Same recognizer options as TextRecognizerHandler (the channel path), so
  // native auto-capture sees exactly what the old Dart-driven path saw.
  private val recognizer =
    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

  // Finds the document's corners on the same frames, so Dart can refuse a
  // capture that cuts one off (the passport MRZ along the bottom edge).
  private val borders = DocumentBorderDetector()

  @Volatile private var sensorRotation = 0
  @Volatile private var analyzing = false

  // Extra clockwise quarter turns the text reader cycles through, one per
  // analysed frame (see [setTextTurns]). Only touched on the analysis executor
  // after the volatile swap, so the index needs no lock.
  @Volatile private var textTurns: IntArray = intArrayOf(0)
  private var textTurnIndex = 0
  private var lastAnalyzedAtMs = 0L

  /** Preview buffer size (the sensor's landscape dims) — reported to Dart so it
   *  can cover-fit the texture at the right proportions. */
  @Volatile var previewBufferWidth = 0
  @Volatile var previewBufferHeight = 0
  val rotationDegrees: Int get() = sensorRotation

  /** Starts the camera + preview + analysis. [onReady] gets the texture id. */
  fun start(onReady: (Long) -> Unit, onError: (String) -> Unit) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
      try {
        cameraProvider = future.get()
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        bindUseCases()
        onReady(textureId)
      } catch (e: Exception) {
        Log.e(tag, "camera start failed", e)
        onError(e.message ?: "camera start failed")
      }
    }, ContextCompat.getMainExecutor(context))
  }

  private fun bindUseCases() {
    val provider = cameraProvider ?: return

    val entry = textures.createSurfaceTexture()
    textureEntry = entry
    val surfaceTexture = entry.surfaceTexture()

    val preview = Preview.Builder().setTargetResolution(PREVIEW_SIZE).build()
    preview.setSurfaceProvider { request ->
      val res = request.resolution
      previewBufferWidth = res.width
      previewBufferHeight = res.height
      surfaceTexture.setDefaultBufferSize(res.width, res.height)
      val surface = Surface(surfaceTexture)
      request.provideSurface(surface, analysisExecutor) { surface.release() }
    }

    // The photo camera binds none: nothing reads its frames.
    val analysis = if (!mode.analyze) null else ImageAnalysis.Builder()
      .setTargetResolution(ANALYSIS_SIZE)
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
      .build()
    analysis?.setAnalyzer(analysisExecutor) { proxy -> onFrame(proxy) }

    // The still MUST keep the preview's aspect ratio: Dart's crop maps the
    // on-screen guide rect into the still assuming both were cover-fit into the
    // same viewfinder box, so a 4:3 still under a 16:9 preview would silently
    // crop the wrong region of the document. Both are 16:9 here.
    val capture = ImageCapture.Builder()
      .setTargetResolution(CAPTURE_SIZE)
      // The scan wants its shot at the instant the gate fires; a plain photo
      // has no gate to keep up with, so it takes the sharper still.
      .setCaptureMode(
        if (mode.analyze) ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY
        else ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY,
      )
      .build()
    imageCapture = capture

    // Deliberately NO setExposurePoint/setFocusPoint. The plugin path pinned a
    // one-shot centre metering action at init, parking focus at whatever
    // distance the first frame saw; CameraX's default continuous AF instead
    // tracks the document as the user moves it in.
    provider.unbindAll()
    val camera: androidx.camera.core.Camera = if (analysis != null) {
      provider.bindToLifecycle(
        this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis, capture,
      )
    } else {
      provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
    }
    this.camera = camera
    sensorRotation = camera.cameraInfo.sensorRotationDegrees
    lifecycleRegistry.currentState = Lifecycle.State.RESUMED

    // Read the preview size from the bound use case, NOT from the surface
    // provider above: CameraX invokes that callback asynchronously, after this
    // method returns, so the fields are still 0 when start()'s onReady reports
    // them to Dart. Dart falls back to a 16:9 default when it gets 0, which
    // happens to match — but the preview aspect is what keeps the crop aligned
    // with the still, so it must be the real value, not a lucky default.
    preview.resolutionInfo?.resolution?.let {
      previewBufferWidth = it.width
      previewBufferHeight = it.height
    }
    Log.i(
      tag,
      "bound preview=${previewBufferWidth}x$previewBufferHeight " +
        "capture=${capture.resolutionInfo?.resolution} rotation=$sensorRotation",
    )
  }

  private fun onFrame(proxy: ImageProxy) {
    val w = proxy.width
    val h = proxy.height
    val rotation = proxy.imageInfo.rotationDegrees
    val now = System.currentTimeMillis()
    val wantText = !analyzing && now - lastAnalyzedAtMs >= ANALYZE_INTERVAL_MS

    // Convert what's needed, then close the proxy immediately — ML Kit runs
    // async off the byte array, so no camera buffer is held while it works and
    // the analysis pipeline stays free-running (which is what keeps the preview
    // smooth).
    var nv21: ByteArray? = null
    try {
      video.offer(proxy, sensorRotation)
      if (wantText) nv21 = Yuv.toNv21(proxy)
    } catch (e: Exception) {
      Log.w(tag, "frame convert failed: ${e.message}")
    } finally {
      proxy.close()
    }

    val frame = nv21 ?: return
    analyzing = true
    lastAnalyzedAtMs = now
    val turns = textTurns
    val turn = TurnedText.normalise(turns[textTurnIndex++ % turns.size])
    val readRotation = TurnedText.mlKitRotation(rotation, turn)
    // ML Kit reports boxes in the frame it read: the upright frame turned by
    // [turn], whose sides swap on an odd turn.
    val readSwapped = readRotation == 90 || readRotation == 270
    val readW = (if (readSwapped) h else w).toFloat()
    val readH = (if (readSwapped) w else h).toFloat()
    // ML Kit reports boxes in the UPRIGHT frame, so a 90/270° sensor means the
    // upright frame is the sensor's dimensions swapped. Normalising here — the
    // one place that knows the rotation — keeps the Dart side free of
    // orientation math.
    val rotated = rotation == 90 || rotation == 270
    val frameW = (if (rotated) h else w).toFloat()
    val frameH = (if (rotated) w else h).toFloat()
    // NV21 starts with the packed Y plane, which is all the border search needs.
    val quad = try {
      // A turned read means the slip stands upright, so look for its corners
      // upright too.
      borders.detect(frame, w, h, rotationDegrees = rotation, upright = turns.any { it != 0 })
    } catch (e: Exception) {
      Log.w(tag, "corner detection failed: ${e.message}")
      null
    }
    fun payloadWith(lines: List<String>): HashMap<String, Any> {
      val payload = HashMap<String, Any>()
      payload["lines"] = lines
      payload["quadSupported"] = true
      payload["frameW"] = frameW.toDouble()
      payload["frameH"] = frameH.toDouble()
      payload["turn"] = turn
      if (quad != null) payload["quad"] = quad.toList()
      return payload
    }
    try {
      val image =
        InputImage.fromByteArray(frame, w, h, readRotation, InputImage.IMAGE_FORMAT_NV21)
      recognizer.process(image)
        .addOnSuccessListener { text ->
          val lines = ArrayList<String>()
          var left = Float.MAX_VALUE
          var top = Float.MAX_VALUE
          var right = 0f
          var bottom = 0f
          for (block in text.textBlocks) {
            for (line in block.lines) lines.add(line.text)
            block.boundingBox?.let { box ->
              if (box.left < left) left = box.left.toFloat()
              if (box.top < top) top = box.top.toFloat()
              if (box.right > right) right = box.right.toFloat()
              if (box.bottom > bottom) bottom = box.bottom.toFloat()
            }
          }
          val payload = payloadWith(lines)
          if (right > left && bottom > top && readW > 0 && readH > 0) {
            // Union of every text block, normalised 0..1 — a proxy for how much
            // of the frame the document's print occupies. Mapped back into the
            // upright frame when the text was read turned.
            payload["bounds"] = TurnedText.boundsToUpright(
              (left / readW).coerceIn(0f, 1f).toDouble(),
              (top / readH).coerceIn(0f, 1f).toDouble(),
              (right / readW).coerceIn(0f, 1f).toDouble(),
              (bottom / readH).coerceIn(0f, 1f).toDouble(),
              turn,
            ).toList()
          }
          onText(payload)
        }
        // The text model may still be downloading; the corners still count.
        .addOnFailureListener { onText(payloadWith(emptyList())) }
        .addOnCompleteListener { analyzing = false }
    } catch (e: Exception) {
      analyzing = false
      Log.w(tag, "text recognition failed: ${e.message}")
      onText(payloadWith(emptyList()))
    }
  }

  // ── Turned reading ──────────────────────────────────────────────────────────

  /**
   * Sets the extra clockwise quarter turns the text reader cycles through, one
   * per analysed frame: `[0]` reads upright, `[3, 1]` alternates for a NIN slip
   * turned upright on a phone held upright, `[3]` holds a turn that worked.
   * Each frame's payload carries the `turn` it was read at. The decision of
   * which turns to try stays in Dart (config/document_turn.dart).
   */
  fun setTextTurns(turns: List<Int>) {
    val clean = turns.map { TurnedText.normalise(it) }
    textTurns = if (clean.isEmpty()) intArrayOf(0) else clean.toIntArray()
  }

  // ── Side clip ───────────────────────────────────────────────────────────────

  /** Starts the side clip. Touches no camera state, so a side change or retake
   *  calls this instead of restarting the session. */
  fun startRecording(audio: Boolean = false) = video.start(audio)

  /** Stops the side clip and returns its MP4 path (or null). */
  fun stopRecording(): String? = video.stop()

  // ── Torch ───────────────────────────────────────────────────────────────────

  /** Whether this camera has a flash unit to switch on at all. */
  fun hasTorch(): Boolean = camera?.cameraInfo?.hasFlashUnit() == true

  /** Turns the torch on/off. The document step's answer to a dim room, which
   *  matters more here than it looks: an unreadable MRZ blocks auto-capture. */
  fun setTorch(enabled: Boolean) {
    try {
      camera?.cameraControl?.enableTorch(enabled)
    } catch (e: Exception) {
      Log.w(tag, "torch failed: ${e.message}")
    }
  }

  // ── Still capture ───────────────────────────────────────────────────────────

  /**
   * Takes the OCR-grade still. Nothing is torn down — preview and analysis keep
   * running — so there is no surface reconfiguration and no sideways flash to
   * hide behind a cover.
   */
  fun captureStill(quality: Int, onResult: (ByteArray?) -> Unit) {
    val capture = imageCapture ?: return onResult(null)
    capture.takePicture(
      analysisExecutor,
      object : ImageCapture.OnImageCapturedCallback() {
        override fun onCaptureSuccess(image: ImageProxy) {
          val bytes = try {
            DocumentStill.uprightJpeg(image, quality)
          } catch (e: Exception) {
            Log.w(tag, "still encode failed: ${e.message}")
            null
          } finally {
            image.close()
          }
          onResult(bytes)
        }

        override fun onError(exception: ImageCaptureException) {
          Log.w(tag, "takePicture failed", exception)
          onResult(null)
        }
      },
    )
  }

  fun dispose() {
    try { video.stop() } catch (_: Exception) {}
    try { cameraProvider?.unbindAll() } catch (_: Exception) {}
    lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    try { recognizer.close() } catch (_: Exception) {}
    try { analysisExecutor.shutdown() } catch (_: Exception) {}
    imageCapture = null
    camera = null
    textureEntry?.release()
    textureEntry = null
  }

  private companion object {
    /** 16:9 — see the aspect-ratio note in [bindUseCases]. */
    val PREVIEW_SIZE = Size(1080, 1920)
    val ANALYSIS_SIZE = Size(720, 1280)

    /** ~1080p, matching what the plugin path asked for (`ResolutionPreset
     *  .veryHigh`) so OCR sharpness is at worst unchanged — and in practice
     *  better, since dropping VideoCapture stops CameraX downgrading it. The
     *  one knob to raise if OCR ever needs more. */
    val CAPTURE_SIZE = Size(1080, 1920)

    /** ML Kit is far slower than the frame rate; matches the 250 ms tick the
     *  Dart-driven path used. */
    const val ANALYZE_INTERVAL_MS = 250L
  }
}
