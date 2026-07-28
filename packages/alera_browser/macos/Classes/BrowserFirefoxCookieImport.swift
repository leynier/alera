import Foundation
import SQLite3

enum BrowserFirefoxCookieImport {
  static func load(
    profile: BrowserImportProfileLocation
  ) throws -> BrowserImportBatch {
    try read(profile.fileURL)
  }

  private static func read(_ source: URL) throws -> BrowserImportBatch {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("alera-firefox-import-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let copy = directory.appendingPathComponent("cookies.sqlite")
      try FileManager.default.copyItem(at: source, to: copy)
      for suffix in ["-wal", "-shm"] {
        let sourceSidecar = URL(fileURLWithPath: source.path + suffix)
        if FileManager.default.fileExists(atPath: sourceSidecar.path) {
          try? FileManager.default.copyItem(
            at: sourceSidecar,
            to: URL(fileURLWithPath: copy.path + suffix)
          )
        }
      }
      defer { try? FileManager.default.removeItem(at: directory) }
      return try query(copy)
    } catch let error as BrowserImportError {
      throw error
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw BrowserImportError("failed", "cookie_database_unreadable")
    }
  }

  private static func query(_ url: URL) throws -> BrowserImportBatch {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK,
      let database
    else {
      if let database { sqlite3_close(database) }
      throw BrowserImportError("failed", "cookie_database_invalid")
    }
    defer { sqlite3_close(database) }
    let columns = columns(database)
    let required = ["host", "name", "value", "path", "expiry", "isSecure", "isHttpOnly"]
    guard required.allSatisfy(columns.contains) else {
      throw BrowserImportError("failed", "cookie_database_schema_unsupported")
    }
    let sameSite = columns.contains("sameSite") ? "sameSite" : "0"
    let originAttributes = columns.contains("originAttributes") ? "originAttributes" : "''"
    let sql = """
      SELECT host, name, value, path, expiry, isSecure, isHttpOnly,
             \(sameSite), \(originAttributes)
      FROM moz_cookies
      ORDER BY host, path, name
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw BrowserImportError("failed", "cookie_database_query_failed")
    }
    defer { sqlite3_finalize(statement) }
    var cookies: [HTTPCookie] = []
    var skipped = 0
    var step = sqlite3_step(statement)
    while step == SQLITE_ROW {
      guard
        let domain = text(statement, 0),
        let name = text(statement, 1),
        let value = text(statement, 2),
        let path = text(statement, 3)
      else {
        throw BrowserImportError("failed", "cookie_database_invalid_row")
      }
      if let attributes = text(statement, 8), !attributes.isEmpty {
        skipped += 1
        step = sqlite3_step(statement)
        continue
      }
      let expiry = sqlite3_column_int64(statement, 4)
      let expires = expiry > 0 ? Date(timeIntervalSince1970: TimeInterval(expiry)) : nil
      if let expires, expires <= Date() {
        skipped += 1
        step = sqlite3_step(statement)
        continue
      }
      let sameSiteValue: String
      switch sqlite3_column_int(statement, 7) {
      case 1:
        sameSiteValue = "lax"
      case 2:
        sameSiteValue = "strict"
      default:
        sameSiteValue = "none"
      }
      var map: [String: Any] = [
        "name": name,
        "value": value,
        "domain": domain,
        "path": path.isEmpty ? "/" : path,
        "secure": sqlite3_column_int(statement, 5) != 0,
        "httpOnly": sqlite3_column_int(statement, 6) != 0,
        "sameSite": sameSiteValue,
        "session": expires == nil,
      ]
      if let expires {
        map["expiresUtc"] = Int64(expires.timeIntervalSince1970 * 1000)
      }
      do {
        cookies.append(try decodeBrowserCookie(map))
      } catch {
        throw BrowserImportError("failed", "cookie_database_invalid_row")
      }
      step = sqlite3_step(statement)
    }
    guard step == SQLITE_DONE else {
      throw BrowserImportError("failed", "cookie_database_query_failed")
    }
    return BrowserImportBatch(cookies: cookies, skipped: skipped)
  }

  private static func columns(_ database: OpaquePointer) -> Set<String> {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(database, "PRAGMA table_info(moz_cookies)", -1, &statement, nil)
        == SQLITE_OK
    else {
      return []
    }
    defer { sqlite3_finalize(statement) }
    var values = Set<String>()
    while sqlite3_step(statement) == SQLITE_ROW {
      if let name = text(statement, 1) { values.insert(name) }
    }
    return values
  }

  private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
  }
}
