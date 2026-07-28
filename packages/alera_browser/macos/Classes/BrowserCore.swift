import Cocoa
import CommonCrypto
import FlutterMacOS

struct BrowserMethodError: Error {
  let code: String
  let message: String

  init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
}

extension Error {
  var asFlutterError: FlutterError {
    if let error = self as? BrowserMethodError {
      return FlutterError(code: error.code, message: error.message, details: nil)
    }
    return FlutterError(
      code: "native_browser_error",
      message: localizedDescription,
      details: nil
    )
  }
}

extension FlutterMethodCall {
  var browserArguments: [String: Any] {
    arguments as? [String: Any] ?? [:]
  }
}

extension Dictionary where Key == String, Value == Any {
  func requiredString(_ key: String) throws -> String {
    guard let value = self[key] as? String, !value.isEmpty else {
      throw BrowserMethodError("invalid_argument", "\"\(key)\" is required.")
    }
    return value
  }

  func optionalString(_ key: String) -> String? {
    guard let value = self[key] as? String, !value.isEmpty else { return nil }
    return value
  }

  func bool(_ key: String, default fallback: Bool = false) -> Bool {
    self[key] as? Bool ?? fallback
  }

  func double(_ key: String, default fallback: Double = 0) -> Double {
    (self[key] as? NSNumber)?.doubleValue ?? fallback
  }
}

func validateIdentifier(_ value: String, kind: String, maximum: Int = 64) throws {
  guard !value.isEmpty, value.count <= maximum else {
    throw BrowserMethodError(
      "invalid_\(kind)_id",
      "The \(kind) id must contain between 1 and \(maximum) characters."
    )
  }
  let allowed = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
  guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
    throw BrowserMethodError(
      "invalid_\(kind)_id",
      "The \(kind) id contains unsupported characters."
    )
  }
}

func stableProfileUUID(_ profileID: String) -> UUID {
  let applicationID = Bundle.main.bundleIdentifier ?? "dev.leynier.alera"
  let input = Data("\(applicationID).browser.profile:\(profileID)".utf8)
  var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
  input.withUnsafeBytes { bytes in
    _ = CC_SHA256(bytes.baseAddress, CC_LONG(input.count), &digest)
  }
  digest[6] = (digest[6] & 0x0f) | 0x50
  digest[8] = (digest[8] & 0x3f) | 0x80
  let hex = digest.prefix(16).map { String(format: "%02x", $0) }
  let value = [
    hex[0...3].joined(),
    hex[4...5].joined(),
    hex[6...7].joined(),
    hex[8...9].joined(),
    hex[10...15].joined(),
  ].joined(separator: "-")
  return UUID(uuidString: value)!
}

func javascriptLiteral(_ value: String) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: [value])
  guard
    let encoded = String(data: data, encoding: .utf8),
    encoded.count >= 2
  else {
    throw BrowserMethodError("javascript_encoding_failed", "Could not encode JavaScript input.")
  }
  return String(encoded.dropFirst().dropLast())
}

func privateWrite(_ data: Data, to path: String) throws {
  guard NSString(string: path).isAbsolutePath else {
    throw BrowserMethodError("invalid_destination", "The destination path must be absolute.")
  }
  let url = URL(fileURLWithPath: path).standardizedFileURL
  let parent = url.deletingLastPathComponent()
  var isDirectory: ObjCBool = false
  guard
    FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
    isDirectory.boolValue
  else {
    throw BrowserMethodError("invalid_destination", "The destination directory does not exist.")
  }
  var info = stat()
  guard lstat(url.path, &info) != 0 && errno == ENOENT else {
    throw BrowserMethodError("destination_exists", "The destination already exists.")
  }
  let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
  guard descriptor >= 0 else {
    throw BrowserMethodError("destination_open_failed", String(cString: strerror(errno)))
  }
  var writeError: BrowserMethodError?
  data.withUnsafeBytes { bytes in
    guard let base = bytes.baseAddress else { return }
    var written = 0
    while written < data.count {
      let count = Darwin.write(descriptor, base.advanced(by: written), data.count - written)
      if count <= 0 {
        writeError = BrowserMethodError(
          "destination_write_failed", String(cString: strerror(errno)))
        break
      }
      written += count
    }
  }
  if close(descriptor) != 0, writeError == nil {
    writeError = BrowserMethodError("destination_write_failed", String(cString: strerror(errno)))
  }
  if let writeError {
    try? FileManager.default.removeItem(at: url)
    throw writeError
  }
}

func artifactValue(
  path: String,
  mimeType: String,
  size: Int,
  width: Int? = nil,
  height: Int? = nil,
  suggestedFileName: String? = nil
) -> [String: Any] {
  var value: [String: Any] = [
    "path": URL(fileURLWithPath: path).standardizedFileURL.path,
    "mimeType": mimeType,
    "sizeBytes": size,
  ]
  if let width { value["width"] = width }
  if let height { value["height"] = height }
  if let suggestedFileName { value["suggestedFileName"] = suggestedFileName }
  return value
}
