import Flutter
import UIKit
import Vision

/// On-device document-edge detection for auto-capture, via Apple Vision.
///
/// Two requests, in preference order:
///   • `VNDetectDocumentSegmentationRequest` (iOS 15+) — purpose-built for
///     documents; returns a quad even against a low-contrast background and
///     copes with perspective.
///   • `VNDetectRectanglesRequest` — the fallback on iOS 13/14. Needs more
///     contrast and reports more false positives, hence the tighter aspect and
///     confidence bounds below.
///
/// Returns the document's normalized bounding box and its four corners; the
/// Dart side decides whether that's centred and large enough to capture, and
/// whether every corner is in view (document_corners.dart). Keeping the policy in
/// Dart means the thresholds are tunable without a native rebuild.
public class DocumentDetector: NSObject, FlutterPlugin {
  private let workQueue = DispatchQueue(label: "co.myazahq.kyc.docdetect", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/document_detection",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(DocumentDetector(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "detect":
      detect(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func detect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let planes = args["planes"] as? [[String: Any]],
      let first = planes.first,
      let typed = first["bytes"] as? FlutterStandardTypedData,
      let bytesPerRow = first["bytesPerRow"] as? Int
    else {
      result(nil)
      return
    }
    let data = typed.data

    workQueue.async {
      guard
        let pixelBuffer = KycSdkFlutterPlugin.makeBGRAPixelBuffer(
          data: data, width: width, height: height, bytesPerRow: bytesPerRow
        )
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      // Read the frame the way the screen shows it. The Flutter camera plugin
      // hands over frames already turned to the phone's (portrait) orientation;
      // `.right` on those, copied from the React Native SDK whose frames are
      // landscape, laid an upright NIN slip on its side, so it never matched
      // its shape and its corners fell outside the visible part of the frame.
      let orientation = Self.uprightOrientation(width: width, height: height)
      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]
      )

      // A landscape frame turned upright swaps its sides. The Dart side
      // compares the document's true aspect against the expected ID aspect,
      // and that comparison is meaningless without the frame's upright size.
      let turned = orientation == .right
      let orientedWidth = Double(turned ? height : width)
      let orientedHeight = Double(turned ? width : height)

      var payload: [String: Any]? = nil
      if #available(iOS 15.0, *) {
        payload = Self.segmentation(handler)
      }
      if payload == nil {
        payload = Self.rectangle(handler)
      }

      if var p = payload,
         let w = p["width"] as? Double,
         let h = p["height"] as? Double,
         w > 0, h > 0 {
        p["aspectRatio"] = (w * orientedWidth) / (h * orientedHeight)
        payload = p
      }

      // Brightness always rides along, INCLUDING when nothing was detected —
      // "too dark to see anything" is precisely the case where the user needs
      // to be told, and a nil payload could never carry that.
      var out = payload ?? [:]
      // Tells Dart this detector reports corners, so an empty result means "no
      // document" rather than "this device cannot tell".
      out["quadSupported"] = true
      // The upright frame the box and the quad were measured in.
      out["frameWidth"] = orientedWidth
      out["frameHeight"] = orientedHeight
      out["brightness"] = Self.meanBrightness(
        data: data, width: width, height: height, bytesPerRow: bytesPerRow
      )
      DispatchQueue.main.async { result(out) }
    }
  }

  /// How Vision must read a camera frame of this size to see it upright on a
  /// phone held upright: a landscape (sensor) frame a quarter turn clockwise,
  /// a portrait frame as it is. The text recognizer reads frames the same way.
  static func uprightOrientation(width: Int, height: Int) -> CGImagePropertyOrientation {
    width > height ? .right : .up
  }

  /// Apple's document finder. Only a confident find of some size counts, as in
  /// the React Native SDK: taking whatever it returned first, however faint or
  /// small, meant a worn paper slip read as nothing and the rectangle search
  /// below never ran.
  @available(iOS 15.0, *)
  private static func segmentation(_ handler: VNImageRequestHandler) -> [String: Any]? {
    let request = VNDetectDocumentSegmentationRequest()
    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    guard
      let best = request.results?.first,
      best.confidence >= 0.6,
      best.boundingBox.width * best.boundingBox.height >= 0.04
    else { return nil }
    return box(best, source: "segmentation")
  }

  private static func rectangle(_ handler: VNImageRequestHandler) -> [String: Any]? {
    let request = VNDetectRectanglesRequest()
    // Vision's aspect is short side ÷ long side. An ID card is ~0.63, a passport
    // page ~0.70 and a NIN slip ~0.48 (paper slips run 2.00 to 2.32 long); allow a
    // band that admits all three at an angle, but not so wide that a laptop edge
    // or table qualifies. Short over long is orientation-free, so a slip turned
    // upright on a phone held upright (config/document_turn.dart) passes too;
    // the `aspectRatio` reported to Dart is width over height as framed, and
    // the Dart gate expects 1 / 2.07 while the slip is turned.
    request.minimumAspectRatio = 0.4
    request.maximumAspectRatio = 1.0
    // As the React Native SDK: an upright slip spans about half the frame's
    // width, so 0.3 lost it as soon as it was held a little back.
    request.minimumSize = 0.2
    // Near-square corners, generous because a slip is rarely flat to the lens.
    request.quadratureTolerance = 30
    request.minimumConfidence = 0.6
    // Several candidates: asked for one, Vision returns the rectangle it is
    // surest of, which on a desk is often a laptop or table running off the
    // edge while a worn slip inside the frame is never reported.
    request.maximumObservations = 8

    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    guard let best = Self.best(request.results ?? []) else { return nil }
    return box(best, source: "rectangle")
  }

  /// One wholly inside the picture if any, the largest of those; otherwise the
  /// largest, so the gate still says a corner is cut off. Mirrors the React
  /// Native SDK's HybridMyazaRectDetector.
  private static func best(_ all: [VNRectangleObservation]) -> VNRectangleObservation? {
    // Written out with explicit types: as one nested closure chain, Xcode's
    // type checker gave up on it ("unable to type-check this expression in
    // reasonable time") in integrators' builds.
    let inside: [VNRectangleObservation] = all.filter { (o: VNRectangleObservation) -> Bool in
      Self.isInsideFrame(o)
    }
    let pool: [VNRectangleObservation] = inside.isEmpty ? all : inside
    return pool.max { (a: VNRectangleObservation, b: VNRectangleObservation) -> Bool in
      Self.area(a) < Self.area(b)
    }
  }

  private static func area(_ o: VNRectangleObservation) -> CGFloat {
    let size: CGSize = o.boundingBox.size
    return size.width * size.height
  }

  private static func isInsideFrame(_ o: VNRectangleObservation) -> Bool {
    let corners: [CGPoint] = [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft]
    let low: CGFloat = 0.01
    let high: CGFloat = 0.99
    for p in corners {
      if p.x <= low || p.x >= high { return false }
      if p.y <= low || p.y >= high { return false }
    }
    return true
  }

  /// Mean luma over a coarse grid of the BGRA frame, 0..1. Sampled rather than
  /// summed: this runs per frame beside detection, and a full pass would cost
  /// more than the detection it accompanies for no extra accuracy.
  private static func meanBrightness(
    data: Data, width: Int, height: Int, bytesPerRow: Int
  ) -> Double {
    let stepX = max(1, width / 32)
    let stepY = max(1, height / 32)
    var total = 0.0
    var count = 0

    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      let bytes = base.assumingMemoryBound(to: UInt8.self)
      var y = 0
      while y < height {
        var x = 0
        while x < width {
          let offset = y * bytesPerRow + x * 4
          guard offset + 2 < raw.count else { break }
          // BGRA
          let b = Double(bytes[offset])
          let g = Double(bytes[offset + 1])
          let r = Double(bytes[offset + 2])
          total += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
          count += 1
          x += stepX
        }
        y += stepY
      }
    }
    return count == 0 ? 0.5 : total / Double(count)
  }

  /// Vision's origin is bottom-left; Flutter's is top-left. Flip Y so the Dart
  /// side can compare directly against its own guide rect.
  ///
  /// Read with [uprightOrientation], Vision's coordinates are already UPRIGHT.
  /// The quad is x, y for top-left, top-right, bottom-right, bottom-left.
  private static func box(
    _ observation: VNRectangleObservation, source: String
  ) -> [String: Any] {
    let rect = observation.boundingBox
    let corners = [
      observation.topLeft, observation.topRight,
      observation.bottomRight, observation.bottomLeft,
    ]
    var quad: [Double] = []
    for p in corners {
      quad.append(Double(p.x))
      quad.append(Double(1.0 - p.y))
    }
    return [
      "x": Double(rect.origin.x),
      "y": Double(1.0 - rect.origin.y - rect.size.height),
      "width": Double(rect.size.width),
      "height": Double(rect.size.height),
      "confidence": Double(observation.confidence),
      "source": source,
      "quad": quad,
    ]
  }
}
