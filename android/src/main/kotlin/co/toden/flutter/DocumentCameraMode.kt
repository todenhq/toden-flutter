package co.toden.flutter

/**
 * What a [DocumentCamera] session runs besides the preview and the still.
 *
 * The scan analyses every frame (text, corners, the side clip). The in-SDK
 * "take a photo" camera wants only the upright preview, the torch and a still,
 * so it starts with [analyze] off: no ImageAnalysis use case is bound at all,
 * which leaves CameraX free to give the preview and the still their best
 * streams.
 */
data class DocumentCameraMode(val analyze: Boolean = true) {
  companion object {
    /** Read from the `start` call's arguments. Only an explicit
     *  `analyze: false` turns analysis off, so a caller that sends nothing
     *  (the scan, or an older Dart build) gets the scan's camera unchanged. */
    fun fromArgs(args: Any?): DocumentCameraMode =
      DocumentCameraMode(analyze = (args as? Map<*, *>)?.get("analyze") != false)
  }
}
