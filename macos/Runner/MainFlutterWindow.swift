import Cocoa
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let previewQueue = DispatchQueue(label: "musha-viewer.image-preview")
    let previewChannel = FlutterMethodChannel(
      name: "musha_viewer/image_preview", binaryMessenger: flutterViewController.engine.binaryMessenger)
    previewChannel.setMethodCallHandler { call, result in
      guard call.method == "decode", let input = call.arguments as? FlutterStandardTypedData else {
        result(FlutterMethodNotImplemented)
        return
      }
      previewQueue.async {
        let output: Data? = autoreleasepool {
          let maxBytes = 64 * 1024 * 1024
          guard input.data.count <= maxBytes,
                let source = CGImageSourceCreateWithData(input.data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width > 0, height > 0 else { return nil }
          let longest = Double(max(width, height))
          let scale = min(1.0, sqrt(40_000_000.0 / Double(width) / Double(height)))
          let maxDimension = max(1, Int(min(40_000_000.0, floor(longest * scale))))
          guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxDimension
                ] as CFDictionary) else { return nil }
          let data = NSMutableData()
          guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
          CGImageDestinationAddImage(destination, image, nil)
          guard CGImageDestinationFinalize(destination), data.length <= maxBytes else { return nil }
          return data as Data
        }
        DispatchQueue.main.async {
          if let output = output {
            result(FlutterStandardTypedData(bytes: output))
          } else {
            result(FlutterError(code: "preview_unavailable", message: "ImageIO preview unavailable or exceeds limits", details: nil))
          }
        }
      }
    }

    super.awakeFromNib()
  }
}
