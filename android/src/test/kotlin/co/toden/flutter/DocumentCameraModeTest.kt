package co.toden.flutter

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentCameraModeTest {
  @Test
  fun theScanKeepsItsAnalysisWhenNothingIsSent() {
    assertTrue(DocumentCameraMode.fromArgs(null).analyze)
    assertTrue(DocumentCameraMode.fromArgs(emptyMap<String, Any>()).analyze)
    assertTrue(DocumentCameraMode().analyze)
  }

  @Test
  fun onlyAnExplicitFalseTurnsAnalysisOff() {
    assertFalse(DocumentCameraMode.fromArgs(mapOf("analyze" to false)).analyze)
    assertTrue(DocumentCameraMode.fromArgs(mapOf("analyze" to true)).analyze)
    // Anything that is not a boolean false is the scan's camera.
    assertTrue(DocumentCameraMode.fromArgs(mapOf("analyze" to "false")).analyze)
    assertTrue(DocumentCameraMode.fromArgs(mapOf("analyze" to null)).analyze)
    assertTrue(DocumentCameraMode.fromArgs("analyze").analyze)
  }
}
