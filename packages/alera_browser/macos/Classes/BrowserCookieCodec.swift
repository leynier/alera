import Foundation

struct BrowserCookieKey: Hashable {
  let name: String
  let domain: String
  let path: String

  init(_ cookie: HTTPCookie) {
    name = cookie.name
    domain = cookie.domain.lowercased()
    path = cookie.path
  }
}

func browserCookieValue(_ cookie: HTTPCookie) -> [String: Any] {
  let sameSite: String
  switch cookie.sameSitePolicy {
  case .sameSiteStrict:
    sameSite = "strict"
  case .sameSiteLax:
    sameSite = "lax"
  default:
    sameSite = "none"
  }
  var value: [String: Any] = [
    "name": cookie.name,
    "value": cookie.value,
    "domain": cookie.domain,
    "path": cookie.path,
    "secure": cookie.isSecure,
    "httpOnly": cookie.isHTTPOnly,
    "sameSite": sameSite,
    "session": cookie.isSessionOnly,
  ]
  if let expires = cookie.expiresDate {
    value["expiresUtc"] = Int64(expires.timeIntervalSince1970 * 1000)
  }
  return value
}

func decodeBrowserCookie(_ value: [String: Any]) throws -> HTTPCookie {
  let name = try value.requiredString("name")
  let cookieValue = value["value"] as? String
  let domain = try value.requiredString("domain")
  let path = value.optionalString("path") ?? "/"
  guard
    let cookieValue,
    !name.contains(where: { $0.isNewline || $0 == ";" }),
    !domain.contains(where: { $0.isWhitespace || $0 == "/" }),
    path.hasPrefix("/"),
    name.utf8.count + cookieValue.utf8.count <= 16_384
  else {
    throw BrowserMethodError("invalid_cookie", "The cookie fields are invalid.")
  }
  var properties: [HTTPCookiePropertyKey: Any] = [
    .name: name,
    .value: cookieValue,
    .domain: domain,
    .path: path,
    .version: 0,
    .secure: value.bool("secure") ? "TRUE" : "FALSE",
    HTTPCookiePropertyKey("HttpOnly"): value.bool("httpOnly") ? "TRUE" : "FALSE",
  ]
  let session = value["session"] as? Bool
  if session != true, let milliseconds = (value["expiresUtc"] as? NSNumber)?.doubleValue {
    let date = Date(timeIntervalSince1970: milliseconds / 1000)
    guard date.timeIntervalSince1970.isFinite else {
      throw BrowserMethodError("invalid_cookie", "The cookie expiration is invalid.")
    }
    properties[.expires] = date
  } else if session == true {
    properties[.discard] = "TRUE"
  }
  switch value["sameSite"] as? String {
  case "strict":
    properties[HTTPCookiePropertyKey("SameSite")] = "Strict"
  case "lax":
    properties[HTTPCookiePropertyKey("SameSite")] = "Lax"
  case "none", nil:
    properties[HTTPCookiePropertyKey("SameSite")] = "None"
  default:
    throw BrowserMethodError("invalid_cookie", "The cookie SameSite value is invalid.")
  }
  guard let cookie = HTTPCookie(properties: properties) else {
    throw BrowserMethodError("invalid_cookie", "Foundation rejected the cookie.")
  }
  return cookie
}

func browserCookie(_ cookie: HTTPCookie, appliesTo url: URL) -> Bool {
  guard let host = url.host?.lowercased() else { return false }
  var domain = cookie.domain.lowercased()
  let acceptsSubdomains = domain.hasPrefix(".")
  if acceptsSubdomains { domain.removeFirst() }
  let domainMatches = host == domain || (acceptsSubdomains && host.hasSuffix(".\(domain)"))
  guard domainMatches else { return false }
  if cookie.isSecure && url.scheme?.lowercased() != "https" { return false }
  let requestPath = url.path.isEmpty ? "/" : url.path
  let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
  guard requestPath.hasPrefix(cookiePath) else { return false }
  if requestPath.count > cookiePath.count,
    !cookiePath.hasSuffix("/"),
    requestPath.dropFirst(cookiePath.count).first != "/"
  {
    return false
  }
  if let expires = cookie.expiresDate, expires <= Date() { return false }
  return true
}

func browserCookiesEquivalent(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
  BrowserCookieKey(lhs) == BrowserCookieKey(rhs)
    && lhs.value == rhs.value
    && lhs.isSecure == rhs.isSecure
    && lhs.isHTTPOnly == rhs.isHTTPOnly
    && lhs.isSessionOnly == rhs.isSessionOnly
    && lhs.sameSitePolicy == rhs.sameSitePolicy
    && abs(
      (lhs.expiresDate?.timeIntervalSince1970 ?? 0)
        - (rhs.expiresDate?.timeIntervalSince1970 ?? 0)) < 1
}
