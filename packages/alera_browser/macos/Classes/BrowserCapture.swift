import Cocoa
import FlutterMacOS
import WebKit

extension AleraBrowserPlugin {
  func handleCaptureMethod(
    _ method: String,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    let page = try page(arguments.requiredString("pageId"))
    let destination = try arguments.requiredString("destinationPath")
    switch method {
    case "capture.screenshot":
      let scale = arguments.double("scale", default: 1)
      guard scale >= 0.25, scale <= 4, scale.isFinite else {
        throw BrowserMethodError(
          "invalid_capture_scale", "Screenshot scale must be from 0.25 to 4.")
      }
      if arguments.bool("fullPage") {
        captureFullPage(page: page, destination: destination, scale: scale, result: result)
      } else {
        captureViewport(page: page, destination: destination, scale: scale, result: result)
      }
    case "capture.pdf":
      capturePDF(
        page: page,
        destination: destination,
        landscape: arguments.bool("landscape"),
        printBackground: arguments.bool("printBackground", default: true),
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func captureViewport(
    page: BrowserPage,
    destination: String,
    scale: Double,
    result: @escaping FlutterResult
  ) {
    guard page.webView.bounds.width > 0, page.webView.bounds.height > 0 else {
      result(
        BrowserMethodError("empty_viewport", "The browser page has no viewport.").asFlutterError
      )
      return
    }
    let configuration = WKSnapshotConfiguration()
    configuration.rect = page.webView.bounds
    configuration.snapshotWidth = NSNumber(value: page.webView.bounds.width * scale)
    configuration.afterScreenUpdates = true
    page.webView.takeSnapshot(with: configuration) { image, error in
      do {
        if let error { throw error }
        guard let image, let encoded = pngData(for: image) else {
          throw BrowserMethodError("screenshot_failed", "WebKit returned no screenshot.")
        }
        try privateWrite(encoded.data, to: destination)
        result(
          artifactValue(
            path: destination,
            mimeType: "image/png",
            size: encoded.data.count,
            width: encoded.width,
            height: encoded.height
          )
        )
      } catch {
        result(error.asFlutterError)
      }
    }
  }

  private func captureFullPage(
    page: BrowserPage,
    destination: String,
    scale: Double,
    result: @escaping FlutterResult
  ) {
    let script = """
      (() => ({
        width: Math.max(document.documentElement.scrollWidth, document.body?.scrollWidth || 0, innerWidth),
        height: Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0, innerHeight),
        viewportWidth: innerWidth,
        viewportHeight: innerHeight,
        scrollX,
        scrollY,
      }))()
      """
    page.webView.evaluateJavaScript(script) { [weak page] value, error in
      guard let page else { return }
      do {
        if let error { throw error }
        guard let metrics = value as? [String: Any] else {
          throw BrowserMethodError("screenshot_failed", "WebKit returned invalid page dimensions.")
        }
        let capture = try FullPageCapture(
          page: page,
          destination: destination,
          scale: scale,
          metrics: metrics,
          result: result
        )
        capture.run()
      } catch {
        result(error.asFlutterError)
      }
    }
  }

  private func capturePDF(
    page: BrowserPage,
    destination: String,
    landscape: Bool,
    printBackground: Bool,
    result: @escaping FlutterResult
  ) {
    let identifier = "alera-pdf-\(UUID().uuidString)"
    let css = [
      landscape ? "@page { size: landscape; }" : "@page { size: portrait; }",
      printBackground
        ? "* { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }"
        : "* { -webkit-print-color-adjust: economy !important; print-color-adjust: economy !important; }",
    ].joined()
    guard let cssLiteral = try? javascriptLiteral(css) else {
      result(
        BrowserMethodError("pdf_failed", "Could not prepare the PDF stylesheet.")
          .asFlutterError
      )
      return
    }
    let setup = """
      (() => {
        const style = document.createElement('style');
        style.id = '\(identifier)';
        style.textContent = \(cssLiteral);
        document.head.appendChild(style);
        return {
          width: Math.max(document.documentElement.scrollWidth, document.body?.scrollWidth || 0, innerWidth),
          height: Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0, innerHeight),
        };
      })()
      """
    page.webView.evaluateJavaScript(setup) { [weak page] value, error in
      guard let page else { return }
      if let error {
        result(BrowserMethodError("pdf_failed", error.localizedDescription).asFlutterError)
        return
      }
      guard
        let metrics = value as? [String: Any],
        let width = (metrics["width"] as? NSNumber)?.doubleValue,
        let height = (metrics["height"] as? NSNumber)?.doubleValue,
        width > 0, height > 0
      else {
        result(
          BrowserMethodError("pdf_failed", "WebKit returned invalid page dimensions.")
            .asFlutterError
        )
        return
      }
      let configuration = WKPDFConfiguration()
      configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
      configuration.allowTransparentBackground = !printBackground
      page.webView.createPDF(configuration: configuration) { pdfResult in
        page.webView.evaluateJavaScript(
          "document.getElementById('\(identifier)')?.remove()"
        )
        do {
          let data = try pdfResult.get()
          try privateWrite(data, to: destination)
          result(
            artifactValue(
              path: destination,
              mimeType: "application/pdf",
              size: data.count
            )
          )
        } catch {
          result(error.asFlutterError)
        }
      }
    }
  }
}

private func pngData(for image: NSImage) -> (data: Data, width: Int, height: Int)? {
  guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let data = bitmap.representation(using: .png, properties: [:])
  else {
    return nil
  }
  return (data, bitmap.pixelsWide, bitmap.pixelsHigh)
}

private final class FullPageCapture {
  let page: BrowserPage
  let destination: String
  let scale: Double
  let width: Double
  let height: Double
  let viewportWidth: Double
  let viewportHeight: Double
  let originalX: Double
  let originalY: Double
  let result: FlutterResult
  let positions: [(Double, Double)]
  let bitmap: NSBitmapImageRep
  var index = 0

  init(
    page: BrowserPage,
    destination: String,
    scale: Double,
    metrics: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    func number(_ key: String) -> Double? {
      (metrics[key] as? NSNumber)?.doubleValue
    }
    guard
      let width = number("width"),
      let height = number("height"),
      let viewportWidth = number("viewportWidth"),
      let viewportHeight = number("viewportHeight"),
      width > 0, height > 0, viewportWidth > 0, viewportHeight > 0
    else {
      throw BrowserMethodError("screenshot_failed", "The full-page dimensions are invalid.")
    }
    let pixelWidth = Int(ceil(width * scale))
    let pixelHeight = Int(ceil(height * scale))
    guard
      pixelWidth <= 32_768,
      pixelHeight <= 32_768,
      Int64(pixelWidth) * Int64(pixelHeight) <= 40_000_000
    else {
      throw BrowserMethodError("capture_too_large", "The full-page screenshot is too large.")
    }
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      throw BrowserMethodError("screenshot_failed", "Could not allocate the screenshot buffer.")
    }
    self.page = page
    self.destination = destination
    self.scale = scale
    self.width = width
    self.height = height
    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight
    originalX = number("scrollX") ?? 0
    originalY = number("scrollY") ?? 0
    self.result = result
    self.bitmap = bitmap
    let xValues = Self.tileOrigins(total: width, viewport: viewportWidth)
    let yValues = Self.tileOrigins(total: height, viewport: viewportHeight)
    positions = yValues.flatMap { y in xValues.map { x in (x, y) } }
  }

  func run() {
    guard index < positions.count else {
      finish()
      return
    }
    let (x, y) = positions[index]
    let script = "window.scrollTo(\(x), \(y)); ({x:scrollX,y:scrollY})"
    page.webView.evaluateJavaScript(script) { [weak self] value, error in
      guard let self else { return }
      if let error {
        fail(error)
        return
      }
      let actual = value as? [String: Any]
      let actualX = (actual?["x"] as? NSNumber)?.doubleValue ?? x
      let actualY = (actual?["y"] as? NSNumber)?.doubleValue ?? y
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) {
        self.snapshotTile(x: actualX, y: actualY)
      }
    }
  }

  private func snapshotTile(x: Double, y: Double) {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = page.webView.bounds
    configuration.snapshotWidth = NSNumber(value: viewportWidth * scale)
    configuration.afterScreenUpdates = true
    page.webView.takeSnapshot(with: configuration) { [weak self] image, error in
      guard let self else { return }
      if let error {
        fail(error)
        return
      }
      guard let image else {
        fail(BrowserMethodError("screenshot_failed", "WebKit returned an empty tile."))
        return
      }
      draw(image: image, x: x, y: y)
      index += 1
      run()
    }
  }

  private func draw(image: NSImage, x: Double, y: Double) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(
      in: NSRect(
        x: x * scale,
        y: (height - y - viewportHeight) * scale,
        width: viewportWidth * scale,
        height: viewportHeight * scale
      ),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
  }

  private func finish() {
    restoreScroll()
    do {
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw BrowserMethodError("screenshot_failed", "Could not encode the screenshot.")
      }
      try privateWrite(data, to: destination)
      result(
        artifactValue(
          path: destination,
          mimeType: "image/png",
          size: data.count,
          width: bitmap.pixelsWide,
          height: bitmap.pixelsHigh
        )
      )
    } catch {
      result(error.asFlutterError)
    }
  }

  private func fail(_ error: Error) {
    restoreScroll()
    result(error.asFlutterError)
  }

  private func restoreScroll() {
    page.webView.evaluateJavaScript("window.scrollTo(\(originalX), \(originalY))")
  }

  private static func tileOrigins(total: Double, viewport: Double) -> [Double] {
    let maximum = max(0, total - viewport)
    guard maximum > 0 else { return [0] }
    var values: [Double] = []
    var position = 0.0
    while position < maximum {
      values.append(position)
      position += viewport
    }
    if values.last != maximum { values.append(maximum) }
    return values
  }
}
