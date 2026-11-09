package co.toden.flutter

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Process
import android.util.Log
import java.nio.ByteBuffer

/**
 * The sound for a document or liveness clip: the microphone, encoded to AAC on its own
 * thread and handed to [Mp4FrameEncoder], which owns the file.
 *
 * Best-effort from end to end. If the permission is missing or the microphone
 * or encoder will not start, [createOrNull] answers null and the clip is silent.
 * A failure mid-clip just ends the sound.
 *
 * The muxer has to know every track before it starts, which happens on the
 * first video frame, so [format] is a fixed description rather than the
 * encoder's own output format, which only exists once audio has been encoded.
 */
class Mp4AudioTrack private constructor(
  private val record: AudioRecord,
  private val codec: MediaCodec,
) {
  private var thread: Thread? = null
  @Volatile private var running = false

  val format: MediaFormat = trackFormat()

  fun start(sink: (ByteBuffer, MediaCodec.BufferInfo) -> Unit) {
    running = true
    thread = Thread({ pump(sink) }, "kyc-document-audio").also { it.start() }
  }

  /** Blocks briefly while the thread finishes. Safe if never started. */
  fun stop() {
    running = false
    try { thread?.join(STOP_WAIT_MS) } catch (_: InterruptedException) {}
    thread = null
    try { record.stop() } catch (_: Exception) {}
    try { record.release() } catch (_: Exception) {}
    try { codec.stop() } catch (_: Exception) {}
    try { codec.release() } catch (_: Exception) {}
  }

  private fun pump(sink: (ByteBuffer, MediaCodec.BufferInfo) -> Unit) {
    val info = MediaCodec.BufferInfo()
    var samples = 0L
    try {
      record.startRecording()
      while (running) {
        val inIndex = codec.dequeueInputBuffer(WAIT_US)
        if (inIndex >= 0) {
          val input = codec.getInputBuffer(inIndex) ?: continue
          input.clear()
          val read = record.read(input, minOf(input.remaining(), READ_BYTES))
          // A negative read is an AudioRecord error, not a pause.
          if (read < 0) throw IllegalStateException("read failed: $read")
          codec.queueInputBuffer(inIndex, 0, read, ptsUsFor(samples), 0)
          samples += read / BYTES_PER_SAMPLE
        }
        drain(sink, info)
      }
    } catch (e: Exception) {
      // The clip goes on without further sound.
      Log.w(TAG, "audio stopped: ${e.message}")
    }
  }

  private fun drain(
    sink: (ByteBuffer, MediaCodec.BufferInfo) -> Unit,
    info: MediaCodec.BufferInfo,
  ) {
    while (true) {
      val outIndex = codec.dequeueOutputBuffer(info, 0)
      if (outIndex < 0) {
        if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) return
        continue // format or buffer change
      }
      val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
      val output = codec.getOutputBuffer(outIndex)
      if (output != null && info.size > 0 && !isConfig) {
        output.position(info.offset)
        output.limit(info.offset + info.size)
        sink(output, info)
      }
      codec.releaseOutputBuffer(outIndex, false)
    }
  }

  companion object {
    private const val TAG = "KycMp4Audio"
    const val SAMPLE_RATE = 44_100
    private const val BIT_RATE = 64_000
    private const val BYTES_PER_SAMPLE = 2
    private const val READ_BYTES = 2_048
    private const val WAIT_US = 10_000L
    private const val STOP_WAIT_MS = 500L

    /** Time of the sample at [samples], in microseconds. */
    fun ptsUsFor(samples: Long): Long = samples * 1_000_000L / SAMPLE_RATE

    /** AudioSpecificConfig: AAC-LC, 44.1 kHz, mono. */
    fun audioSpecificConfig(): ByteArray = byteArrayOf(0x12, 0x08)

    private fun trackFormat(): MediaFormat =
      MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
        setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
        setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        setByteBuffer("csd-0", ByteBuffer.wrap(audioSpecificConfig()))
      }

    /** Null when the clip has to stay silent. */
    @SuppressLint("MissingPermission") // checked first
    fun createOrNull(context: Context): Mp4AudioTrack? {
      // Context.checkSelfPermission is API 23; this SDK runs from API 21.
      val granted = context.checkPermission(
        Manifest.permission.RECORD_AUDIO, Process.myPid(), Process.myUid(),
      ) == PackageManager.PERMISSION_GRANTED
      if (!granted) return null
      var record: AudioRecord? = null
      var codec: MediaCodec? = null
      try {
        val minBuffer = AudioRecord.getMinBufferSize(
          SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) return null
        record = AudioRecord(
          MediaRecorder.AudioSource.CAMCORDER,
          SAMPLE_RATE,
          AudioFormat.CHANNEL_IN_MONO,
          AudioFormat.ENCODING_PCM_16BIT,
          minBuffer * 2,
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
          record.release()
          return null
        }
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
          val config = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1,
          ).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
          }
          configure(config, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
          start()
        }
        return Mp4AudioTrack(record, codec)
      } catch (e: Exception) {
        Log.w(TAG, "microphone unavailable: ${e.message}")
        try { record?.release() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        return null
      }
    }
  }
}
