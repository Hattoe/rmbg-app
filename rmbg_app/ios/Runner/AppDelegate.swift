import UIKit
import Flutter
import CoreML
import Vision

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  private var model: VNCoreMLModel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.rmbg.app/background_removal",
      binaryMessenger: controller.binaryMessenger
    )

    if let modelURL = Bundle.main.url(forResource: "u2net", withExtension: "mlmodelc") {
      let config = MLModelConfiguration()
      config.computeUnits = .all
      if let mlModel = try? MLModel(contentsOf: modelURL, configuration: config),
         let vnModel = try? VNCoreMLModel(for: mlModel) {
        self.model = vnModel
        print("U2Net model loaded successfully")
      }
    } else {
      print("Warning: u2net.mlmodelc not found in bundle")
    }

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "removeBackground":
        guard let args = call.arguments as? [String: Any],
              let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "INVALID_ARGS",
                             message: "imageBytes required",
                             details: nil))
          return
        }
        self?.removeBackground(imageData: imageBytes.data, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func removeBackground(imageData: Data, result: @escaping FlutterResult) {
    guard let model = self.model else {
      result(FlutterError(code: "MODEL_NOT_LOADED",
                         message: "Model failed to load",
                         details: nil))
      return
    }

    guard let uiImage = UIImage(data: imageData),
          let cgImage = uiImage.cgImage else {
      result(FlutterError(code: "INVALID_IMAGE",
                         message: "Could not decode image",
                         details: nil))
      return
    }

    let request = VNCoreMLRequest(model: model) { req, err in
      if let err = err {
        result(FlutterError(code: "INFERENCE_ERROR",
                           message: err.localizedDescription,
                           details: nil))
        return
      }

      guard let observations = req.results as? [VNCoreMLFeatureValueObservation],
            let maskArray = observations.first?.featureValue.multiArrayValue else {
        result(FlutterError(code: "NO_OUTPUT",
                           message: "Model produced no output",
                           details: nil))
        return
      }

      let width = 320
      let height = 320
      var pixels = [UInt8](repeating: 0, count: width * height * 4)

      UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
      uiImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
      let resized = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()

      guard let resizedCG = resized?.cgImage,
            let dataProvider = resizedCG.dataProvider,
            let pixelData = dataProvider.data else {
        result(FlutterError(code: "RESIZE_ERROR", message: "Could not resize image", details: nil))
        return
      }

      let srcBytes = CFDataGetBytePtr(pixelData)!

      for i in 0..<(width * height) {
        let maskVal = maskArray[i].floatValue
        let alpha = UInt8(min(255, max(0, Int(maskVal * 255))))
        pixels[i*4 + 0] = srcBytes[i*4 + 0]
        pixels[i*4 + 1] = srcBytes[i*4 + 1]
        pixels[i*4 + 2] = srcBytes[i*4 + 2]
        pixels[i*4 + 3] = alpha
      }

      let colorSpace = CGColorSpaceCreateDeviceRGB()
      guard let context = CGContext(
        data: &pixels,
        width: width, height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ), let outputCG = context.makeImage() else {
        result(FlutterError(code: "RENDER_ERROR", message: "Could not render output", details: nil))
        return
      }

      let outputImage = UIImage(cgImage: outputCG)
      if let pngData = outputImage.pngData() {
        result(FlutterStandardTypedData(bytes: pngData))
      } else {
        result(FlutterError(code: "ENCODE_ERROR", message: "Could not encode PNG", details: nil))
      }
    }

    request.imageCropAndScaleOption = .scaleFit
    let handler = VNImageRequestHandler(cgImage: cgImage)
    DispatchQueue.global(qos: .userInitiated).async {
      try? handler.perform([request])
    }
  }
}