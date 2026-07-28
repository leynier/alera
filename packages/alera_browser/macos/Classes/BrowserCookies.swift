import FlutterMacOS
import WebKit

extension AleraBrowserPlugin {
  func handleCookieMethod(
    _ method: String,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    let profileID = try arguments.requiredString("profileId")
    let store = try profile(profileID).dataStore.httpCookieStore
    if activeCookieImports.contains(profileID), method != "cookies.get" {
      throw BrowserMethodError(
        "import_in_progress",
        "Cookie writes are unavailable while this profile is importing cookies."
      )
    }
    switch method {
    case "cookies.get":
      let rawURL = try arguments.requiredString("url")
      guard
        let url = URL(string: rawURL),
        ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        url.host != nil
      else {
        throw BrowserMethodError("invalid_url", "A valid HTTP or HTTPS URL is required.")
      }
      store.getAllCookies { cookies in
        result(cookies.filter { browserCookie($0, appliesTo: url) }.map(browserCookieValue))
      }
    case "cookies.set":
      guard let value = arguments["cookie"] as? [String: Any] else {
        throw BrowserMethodError("invalid_cookie", "A cookie map is required.")
      }
      let cookie = try decodeBrowserCookie(value)
      store.setCookie(cookie) {
        store.getAllCookies { cookies in
          if cookies.contains(where: { browserCookiesEquivalent($0, cookie) }) {
            result(nil)
          } else {
            result(
              BrowserMethodError("cookie_write_failed", "WebKit did not retain the cookie.")
                .asFlutterError
            )
          }
        }
      }
    case "cookies.delete":
      store.getAllCookies { cookies in
        let matches = cookies.filter { cookie in
          self.cookie(cookie, matches: arguments)
        }
        self.deleteCookies(matches[...], from: store) {
          result(matches.count)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func cookie(_ cookie: HTTPCookie, matches filter: [String: Any]) -> Bool {
    if let name = filter.optionalString("name"), cookie.name != name { return false }
    if let domain = filter.optionalString("domain"), cookie.domain != domain { return false }
    if let path = filter.optionalString("path"), cookie.path != path { return false }
    if let rawURL = filter.optionalString("url") {
      guard let url = URL(string: rawURL), browserCookie(cookie, appliesTo: url) else {
        return false
      }
    }
    return true
  }

  func deleteCookies(
    _ cookies: ArraySlice<HTTPCookie>,
    from store: WKHTTPCookieStore,
    completion: @escaping () -> Void
  ) {
    guard let first = cookies.first else {
      completion()
      return
    }
    store.delete(first) {
      self.deleteCookies(cookies.dropFirst(), from: store, completion: completion)
    }
  }

  func setCookies(
    _ cookies: ArraySlice<HTTPCookie>,
    in store: WKHTTPCookieStore,
    completion: @escaping () -> Void
  ) {
    guard let first = cookies.first else {
      completion()
      return
    }
    store.setCookie(first) {
      self.setCookies(cookies.dropFirst(), in: store, completion: completion)
    }
  }
}
