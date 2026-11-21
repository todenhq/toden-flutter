import AVFoundation
import Flutter

/// One depth frame of the face from the iPhone's front TrueDepth (Face ID)
/// camera, for Core's depth check (kyc-core docbio/depth-sensor.ts; Dart side
/// lib/src/liveness/depth_frame.dart).
///
/// The `camera` plugin records the liveness step and cannot deliver depth, and
/// its capture session cannot be reached from here. Two sessions on the front
/// camera at once interrupt each other, so this opens its own session only
/// after the Dart side has closed the plugin's camera (just after the selfie),
/// takes one frame and closes again, all within a timeout. It never touches
/// the plugin's session.
///
/// Replies `{width, height, mm}`: millimetres from the camera as little-endian
/// UInt16, row by row, 0 where there is no reading. Replies nil on a device
/// without a TrueDepth camera, without camera permission, or on any failure.
public class DepthFrame: NSObject, FlutterPlugin {
  private var grab: DepthGrab?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/depth_frame",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(DepthFrame(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      // One at a time: a second would fight the first for the camera.
      guard grab == nil else {
        result(nil)
        return
      }
      let timeoutMs = (call.arguments as? [String: Any])?["timeoutMs"] as? Int ?? 2500
      let grab = DepthGrab(timeout: .milliseconds(max(500, min(timeoutMs, 5000))))
      self.grab = grab
      grab.run { [weak self] frame in
        DispatchQueue.main.async {
          self?.grab = nil
          result(frame)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// A single capture: open the TrueDepth camera, wait for a frame that holds
/// something near, convert it, close the camera. Everything runs on [queue],
/// so the delegate, the timeout and the finish never overlap.
private final class DepthGrab: NSObject, AVCaptureDepthDataOutputDelegate {
  /// The first frames after the projector starts can be empty or partial.
  private static let settleFrames = 3
  /// Core's own floor for a face (MIN_FACE_PIXELS) under its 1.5 m cut-off.
  private static let minNearReadings = 200
  private static let nearMm: UInt16 = 1500
  /// About the width Core needs; larger maps are thinned to it.
  private static let targetWidth = 320

  private let queue = DispatchQueue(label: "co.toden.flutter.depth", qos: .userInitiated)
  private let session = AVCaptureSession()
  private let output = AVCaptureDepthDataOutput()
  private let timeout: DispatchTimeInterval
  private var completion: (([String: Any]?) -> Void)?
  private var frames = 0
  /// The best frame so far, answered if none clears the bar before the timeout.
  private var best: (reply: [String: Any], near: Int)?
  private var observers: [NSObjectProtocol] = []

  init(timeout: DispatchTimeInterval) {
    self.timeout = timeout
  }

  func run(_ completion: @escaping ([String: Any]?) -> Void) {
    queue.async {
      self.completion = completion
      guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device)
      else {
        self.finish(nil)
        return
      }
      self.session.beginConfiguration()
      if self.session.canSetSessionPreset(.vga640x480) {
        self.session.sessionPreset = .vga640x480
      }
      guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
        self.session.commitConfiguration()
        self.finish(nil)
        return
      }
      self.session.addInput(input)
      self.session.addOutput(self.output)
      // Raw readings: the filter fills holes from neighbouring pixels and the
      // colour image, inventing values Core would read as the face's shape.
      self.output.isFilteringEnabled = false
      self.output.alwaysDiscardsLateDepthData = true
      self.output.setDelegate(self, callbackQueue: self.queue)
      self.session.commitConfiguration()

      // Another session taking the camera ends this one with nothing.
      let center = NotificationCenter.default
      for name in [Notification.Name.AVCaptureSessionWasInterrupted, .AVCaptureSessionRuntimeError] {
        self.observers.append(
          center.addObserver(forName: name, object: self.session, queue: nil) { [weak self] _ in
            self?.queue.async { self?.finish(nil) }
          })
      }
      self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
        guard let self else { return }
        self.finish(self.best?.reply)
      }
      self.session.startRunning()
    }
  }

  func depthDataOutput(
    _ output: AVCaptureDepthDataOutput,
    didOutput depthData: AVDepthData,
    timestamp: CMTime,
    connection: AVCaptureConnection
  ) {
    guard completion != nil else { return }
    frames += 1
    guard frames > Self.settleFrames else { return }
    // Relative disparity is not distance; Core would read it as millimetres.
    // The TrueDepth camera's maps are absolute.
    guard depthData.depthDataAccuracy == .absolute else { return }
    guard let measured = Self.millimetres(of: depthData) else { return }
    if measured.near > (best?.near ?? -1) { best = measured }
    if measured.near >= Self.minNearReadings { finish(measured.reply) }
  }

  /// Answers once, then closes the camera before the reply leaves, so the
  /// next camera to open finds it free.
  private func finish(_ reply: [String: Any]?) {
    guard let completion else { return }
    self.completion = nil
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    output.setDelegate(nil, callbackQueue: nil)
    if session.isRunning { session.stopRunning() }
    session.beginConfiguration()
    for input in session.inputs { session.removeInput(input) }
    for output in session.outputs { session.removeOutput(output) }
    session.commitConfiguration()
    completion(reply)
  }

  /// The frame in millimetres (UInt16 little-endian), thinned to about
  /// [targetWidth] by taking every n-th reading (never averaging, which would
  /// blend a reading with a hole), and how many readings are near.
  private static func millimetres(of data: AVDepthData) -> (reply: [String: Any], near: Int)? {
    // Depth in metres; a disparity map converts as 1 / disparity.
    let depth = data.depthDataType == kCVPixelFormatType_DepthFloat32
      ? data : data.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
    let map = depth.depthDataMap
    guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
    CVPixelBufferLockBaseAddress(map, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
    let width = CVPixelBufferGetWidth(map)
    let height = CVPixelBufferGetHeight(map)
    let stride = CVPixelBufferGetBytesPerRow(map)
    guard width > 0, height > 0 else { return nil }
    let step = max(1, width / targetWidth)
    let outWidth = (width + step - 1) / step
    let outHeight = (height + step - 1) / step

    var near = 0
    var bytes = Data(count: outWidth * outHeight * 2)
    bytes.withUnsafeMutableBytes { raw in
      let out = raw.bindMemory(to: UInt16.self)
      var i = 0
      for y in Swift.stride(from: 0, to: height, by: step) {
        let row = (base + y * stride).assumingMemoryBound(to: Float32.self)
        for x in Swift.stride(from: 0, to: width, by: step) {
          let metres = row[x]
          // NaN, infinity and nothing-there are all "no reading".
          var mm: UInt16 = 0
          if metres.isFinite && metres > 0 {
            let value = (metres * 1000).rounded()
            if value < Float32(UInt16.max) { mm = UInt16(value) }
          }
          if mm > 0 && mm < nearMm { near += 1 }
          out[i] = mm.littleEndian
          i += 1
        }
      }
    }
    // The map is in the sensor's own orientation (landscape, unmirrored).
    // Core's reading does not depend on orientation, so it is sent as read.
    return (reply: [
      "width": outWidth,
      "height": outHeight,
      "mm": FlutterStandardTypedData(bytes: bytes),
    ], near: near)
  }
}
