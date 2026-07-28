import Foundation

enum BrowserManualCookieImport {
  static func parse(_ json: String) throws -> BrowserImportBatch {
    guard let data = json.data(using: .utf8), data.count <= 16 * 1024 * 1024 else {
      throw BrowserImportError("failed", "manual_json_too_large")
    }
    let root: Any
    do {
      root = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw BrowserImportError("failed", "manual_json_invalid")
    }
    let rawCookies: [Any]
    if let values = root as? [Any] {
      rawCookies = values
    } else if let object = root as? [String: Any],
      let values = object["cookies"] as? [Any]
    {
      rawCookies = values
    } else {
      throw BrowserImportError("failed", "manual_json_invalid")
    }
    guard rawCookies.count <= 100_000 else {
      throw BrowserImportError("failed", "manual_json_too_many_cookies")
    }
    var cookies: [HTTPCookie] = []
    var skipped = 0
    for raw in rawCookies {
      guard let object = raw as? [String: Any] else {
        throw BrowserImportError("failed", "manual_json_invalid_cookie")
      }
      let normalized = try normalize(object)
      do {
        let cookie = try decodeBrowserCookie(normalized)
        if let expires = cookie.expiresDate, expires <= Date() {
          skipped += 1
        } else {
          cookies.append(cookie)
        }
      } catch {
        throw BrowserImportError("failed", "manual_json_invalid_cookie")
      }
    }
    return deduplicatedImportBatch(cookies, skipped: skipped)
  }

  private static func normalize(_ value: [String: Any]) throws -> [String: Any] {
    guard
      let name = value["name"] as? String,
      let cookieValue = value["value"] as? String,
      let domain = (value["domain"] ?? value["host"] ?? value["host_key"]) as? String
    else {
      throw BrowserImportError("failed", "manual_json_invalid_cookie")
    }
    let sameSite = ((value["sameSite"] ?? value["same_site"]) as? String)?
      .lowercased()
      .replacingOccurrences(of: "no_restriction", with: "none")
      .replacingOccurrences(of: "unspecified", with: "none")
    var normalized: [String: Any] = [
      "name": name,
      "value": cookieValue,
      "domain": domain,
      "path": value["path"] as? String ?? "/",
      "secure": bool(value["secure"] ?? value["isSecure"] ?? value["is_secure"]),
      "httpOnly": bool(value["httpOnly"] ?? value["isHttpOnly"] ?? value["is_httponly"]),
      "sameSite": sameSite ?? "none",
    ]
    if let explicitSession = value["session"] as? Bool {
      normalized["session"] = explicitSession
    }
    if let milliseconds = expirationMilliseconds(value) {
      if milliseconds <= 0 {
        normalized["session"] = true
      } else {
        normalized["expiresUtc"] = milliseconds
      }
    }
    return normalized
  }

  private static func bool(_ value: Any?) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      return value == "1" || value.lowercased() == "true"
    }
    return false
  }

  private static func expirationMilliseconds(_ value: [String: Any]) -> Double? {
    if let raw = value["expiresUtc"] as? NSNumber {
      return raw.doubleValue
    }
    if let raw = (value["expirationDate"] ?? value["expires"]) as? NSNumber {
      let number = raw.doubleValue
      return abs(number) >= 10_000_000_000 ? number : number * 1000
    }
    if let raw = value["expires_utc"] as? NSNumber {
      let chromium = raw.doubleValue
      return (chromium - 11_644_473_600_000_000) / 1000
    }
    return nil
  }
}
