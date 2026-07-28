import Foundation

enum BrowserSafariCookieImport {
  static func load(
    profile: BrowserImportProfileLocation
  ) throws -> BrowserImportBatch {
    do {
      let data = try Data(
        contentsOf: profile.fileURL,
        options: [.mappedIfSafe]
      )
      return try parse(data)
    } catch let error as CocoaError where error.code == .fileReadNoPermission {
      throw BrowserImportError("denied", "full_disk_access_required")
    } catch let error as BrowserImportError {
      throw error
    } catch {
      throw BrowserImportError("failed", "safari_cookie_file_unreadable")
    }
  }

  static func parse(_ data: Data) throws -> BrowserImportBatch {
    let reader = BinaryCookieReader(data)
    guard reader.readASCII(4) == "cook", let rawPageCount = reader.readUInt32BE() else {
      throw BrowserImportError("failed", "safari_cookie_file_invalid")
    }
    let pageCount = Int(rawPageCount)
    guard pageCount <= 100_000, pageCount <= reader.remaining / 4 else {
      throw BrowserImportError("failed", "safari_cookie_file_invalid")
    }
    var sizes: [Int] = []
    for _ in 0..<pageCount {
      guard let rawSize = reader.readUInt32BE() else {
        throw BrowserImportError("failed", "safari_cookie_file_invalid")
      }
      sizes.append(Int(rawSize))
    }
    var cookies: [HTTPCookie] = []
    var skipped = 0
    var offset = reader.offset
    for size in sizes {
      guard size >= 8, size <= data.count - offset else {
        throw BrowserImportError("failed", "safari_cookie_file_invalid")
      }
      let page = data.subdata(in: offset..<(offset + size))
      let batch = try parsePage(page)
      cookies.append(contentsOf: batch.cookies)
      skipped += batch.skipped
      offset += size
    }
    return BrowserImportBatch(cookies: cookies, skipped: skipped)
  }

  private static func parsePage(_ data: Data) throws -> BrowserImportBatch {
    let reader = BinaryCookieReader(data)
    guard reader.readUInt32LE() != nil, let rawCount = reader.readUInt32LE() else {
      throw BrowserImportError("failed", "safari_cookie_file_invalid")
    }
    let count = Int(rawCount)
    guard count <= 1_000_000, count <= reader.remaining / 4 else {
      throw BrowserImportError("failed", "safari_cookie_file_invalid")
    }
    var offsets: [Int] = []
    for _ in 0..<count {
      guard let rawOffset = reader.readUInt32LE() else {
        throw BrowserImportError("failed", "safari_cookie_file_invalid")
      }
      offsets.append(Int(rawOffset))
    }
    var cookies: [HTTPCookie] = []
    var skipped = 0
    for offset in offsets {
      guard let record = parseRecord(data, offset: offset) else {
        throw BrowserImportError("failed", "safari_cookie_file_invalid")
      }
      if let expires = record.expiresDate, expires <= Date() {
        skipped += 1
      } else {
        cookies.append(record)
      }
    }
    return BrowserImportBatch(cookies: cookies, skipped: skipped)
  }

  private static func parseRecord(_ data: Data, offset: Int) -> HTTPCookie? {
    guard offset >= 0, offset <= data.count - 56 else { return nil }
    let reader = BinaryCookieReader(data, offset: offset)
    guard let rawSize = reader.readUInt32LE() else { return nil }
    let size = Int(rawSize)
    guard size >= 56, size <= data.count - offset else { return nil }
    guard
      reader.readUInt32LE() != nil,
      let flags = reader.readUInt32LE(),
      reader.readUInt32LE() != nil,
      let domainOffset = reader.readUInt32LE(),
      let nameOffset = reader.readUInt32LE(),
      let pathOffset = reader.readUInt32LE(),
      let valueOffset = reader.readUInt32LE(),
      reader.readUInt32LE() != nil,
      reader.readUInt32LE() != nil,
      let expiresReference = reader.readDoubleLE(),
      reader.readDoubleLE() != nil
    else {
      return nil
    }
    let limit = offset + size
    guard
      let domain = cString(data, base: offset, relative: Int(domainOffset), limit: limit),
      let name = cString(data, base: offset, relative: Int(nameOffset), limit: limit),
      let value = cString(data, base: offset, relative: Int(valueOffset), limit: limit)
    else {
      return nil
    }
    let path = cString(data, base: offset, relative: Int(pathOffset), limit: limit) ?? "/"
    let expires =
      expiresReference > 0
      ? Date(timeIntervalSinceReferenceDate: expiresReference)
      : nil
    var map: [String: Any] = [
      "name": name,
      "value": value,
      "domain": domain,
      "path": path.isEmpty ? "/" : path,
      "secure": flags & 0x1 != 0,
      "httpOnly": flags & 0x4 != 0,
      "sameSite": "none",
      "session": expires == nil,
    ]
    if let expires {
      map["expiresUtc"] = Int64(expires.timeIntervalSince1970 * 1000)
    }
    return try? decodeBrowserCookie(map)
  }

  private static func cString(
    _ data: Data,
    base: Int,
    relative: Int,
    limit: Int
  ) -> String? {
    guard relative >= 0, base <= limit, limit <= data.count, relative < limit - base else {
      return nil
    }
    let start = base + relative
    let end = data[start..<limit].firstIndex(of: 0) ?? limit
    guard end > start else { return "" }
    return String(data: data.subdata(in: start..<end), encoding: .utf8)
  }
}

private final class BinaryCookieReader {
  let data: Data
  private(set) var offset: Int

  init(_ data: Data, offset: Int = 0) {
    self.data = data
    self.offset = offset
  }

  var remaining: Int { data.count - offset }

  func readASCII(_ count: Int) -> String? {
    read(count).flatMap { String(data: $0, encoding: .ascii) }
  }

  func read(_ count: Int) -> Data? {
    guard count >= 0, count <= remaining else { return nil }
    let end = offset + count
    let value = data.subdata(in: offset..<end)
    offset = end
    return value
  }

  func readUInt32BE() -> UInt32? {
    read(4)?.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  func readUInt32LE() -> UInt32? {
    read(4)?.enumerated().reduce(0) {
      $0 | (UInt32($1.element) << UInt32($1.offset * 8))
    }
  }

  func readDoubleLE() -> Double? {
    guard
      let raw = read(8)?.enumerated().reduce(
        UInt64(0),
        {
          $0 | (UInt64($1.element) << UInt64($1.offset * 8))
        })
    else {
      return nil
    }
    return Double(bitPattern: raw)
  }
}
