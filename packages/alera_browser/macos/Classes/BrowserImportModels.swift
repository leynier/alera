import Foundation

struct BrowserImportBatch {
  let cookies: [HTTPCookie]
  let skipped: Int
}

struct BrowserImportError: Error {
  let outcome: String
  let detailCode: String

  init(_ outcome: String = "failed", _ detailCode: String) {
    self.outcome = outcome
    self.detailCode = detailCode
  }
}

struct BrowserImportProfileLocation {
  let name: String
  let fileURL: URL
}

func chromiumProfileDisplayName(
  localStateData: Data?,
  directory: String
) -> String {
  guard
    let localStateData,
    let object = try? JSONSerialization.jsonObject(with: localStateData),
    let root = object as? [String: Any],
    let profile = root["profile"] as? [String: Any],
    let infoCache = profile["info_cache"] as? [String: Any],
    let info = infoCache[directory] as? [String: Any],
    let name = info["name"] as? String,
    !name.isEmpty
  else {
    return directory
  }
  return name
}

func firefoxProfileDisplayName(_ directory: String) -> String {
  guard
    let separator = directory.firstIndex(of: "."),
    separator < directory.index(before: directory.endIndex)
  else {
    return directory
  }
  return String(directory[directory.index(after: separator)...])
}

func selectedBrowserImportProfile(
  _ profiles: [BrowserImportProfileLocation],
  named selectedName: String?
) throws -> BrowserImportProfileLocation {
  guard let selectedName, !selectedName.isEmpty else {
    throw BrowserImportError("failed", "source_profile_required")
  }
  let matches = profiles.filter { $0.name == selectedName }
  guard matches.count == 1 else {
    throw BrowserImportError(
      "failed",
      matches.isEmpty ? "source_profile_not_found" : "source_profile_ambiguous"
    )
  }
  return matches[0]
}

struct ChromiumImportSource {
  let id: String
  let relativeRoot: String
  let keychainLabels: [(service: String, account: String)]

  static let supported: [ChromiumImportSource] = [
    ChromiumImportSource(
      id: "chrome",
      relativeRoot: "Google/Chrome",
      keychainLabels: [("Chrome Safe Storage", "Chrome")]
    ),
    ChromiumImportSource(
      id: "edge",
      relativeRoot: "Microsoft Edge",
      keychainLabels: [("Microsoft Edge Safe Storage", "Microsoft Edge")]
    ),
    ChromiumImportSource(
      id: "arc",
      relativeRoot: "Arc/User Data",
      keychainLabels: [("Arc Safe Storage", "Arc")]
    ),
    ChromiumImportSource(
      id: "brave",
      relativeRoot: "BraveSoftware/Brave-Browser",
      keychainLabels: [("Brave Safe Storage", "Brave")]
    ),
    ChromiumImportSource(
      id: "comet",
      relativeRoot: "Comet",
      keychainLabels: [("Comet Safe Storage", "Comet")]
    ),
    ChromiumImportSource(
      id: "helium",
      relativeRoot: "net.imput.helium",
      keychainLabels: [
        ("Helium Storage Key", "Helium"),
        ("Helium Safe Storage", "Helium"),
        ("net.imput.helium Safe Storage", "net.imput.helium"),
      ]
    ),
  ]

  static func source(id: String) -> ChromiumImportSource? {
    supported.first { $0.id == id }
  }

  var rootURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support")
      .appendingPathComponent(relativeRoot)
  }

  func cookieProfiles() -> [BrowserImportProfileLocation] {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }
    let localState = rootURL.appendingPathComponent("Local State")
    let localStateData: Data?
    if let values = try? localState.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize,
      size <= 16 * 1024 * 1024
    {
      localStateData = try? Data(contentsOf: localState)
    } else {
      localStateData = nil
    }
    return
      entries
      .filter { url in
        let name = url.lastPathComponent
        let directory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        return directory == true
          && (name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-"))
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .compactMap { profile in
        let network = profile.appendingPathComponent("Network/Cookies")
        if FileManager.default.fileExists(atPath: network.path) {
          return BrowserImportProfileLocation(
            name: chromiumProfileDisplayName(
              localStateData: localStateData,
              directory: profile.lastPathComponent
            ),
            fileURL: network
          )
        }
        let primary = profile.appendingPathComponent("Cookies")
        return FileManager.default.fileExists(atPath: primary.path)
          ? BrowserImportProfileLocation(
            name: chromiumProfileDisplayName(
              localStateData: localStateData,
              directory: profile.lastPathComponent
            ),
            fileURL: primary
          )
          : nil
      }
  }
}

func firefoxCookieProfiles() -> [BrowserImportProfileLocation] {
  let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Firefox/Profiles")
  guard
    let profiles = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
  else {
    return []
  }
  return
    profiles
    .sorted { firefoxProfileRank($0.lastPathComponent) < firefoxProfileRank($1.lastPathComponent) }
    .compactMap { profile in
      let database = profile.appendingPathComponent("cookies.sqlite")
      return FileManager.default.fileExists(atPath: database.path)
        ? BrowserImportProfileLocation(
          name: firefoxProfileDisplayName(profile.lastPathComponent),
          fileURL: database
        )
        : nil
    }
}

private func firefoxProfileRank(_ value: String) -> String {
  let lower = value.lowercased()
  if lower.contains("default-release") { return "0-\(lower)" }
  if lower.contains("default") { return "1-\(lower)" }
  return "2-\(lower)"
}

func safariCookieProfiles() -> [BrowserImportProfileLocation] {
  let home = FileManager.default.homeDirectoryForCurrentUser
  var candidates = [
    BrowserImportProfileLocation(
      name: "Default",
      fileURL: home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
    ),
    BrowserImportProfileLocation(
      name: "Safari Container",
      fileURL: home.appendingPathComponent(
        "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
      )
    ),
  ]
  for root in [
    home.appendingPathComponent(
      "Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore"
    ),
    home.appendingPathComponent("Library/WebKit/WebsiteDataStore"),
  ] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      continue
    }
    for case let url as URL in enumerator where url.lastPathComponent == "Cookies.binarycookies" {
      let relative = url.path.dropFirst(root.path.count)
      let storeName =
        relative.split(separator: "/").first.map(String.init)
        ?? url.deletingLastPathComponent().lastPathComponent
      candidates.append(
        BrowserImportProfileLocation(name: storeName, fileURL: url)
      )
    }
  }
  var seen = Set<String>()
  return candidates.filter {
    seen.insert($0.fileURL.path).inserted
      && FileManager.default.fileExists(atPath: $0.fileURL.path)
  }
}

func deduplicatedImportBatch(_ cookies: [HTTPCookie], skipped: Int) -> BrowserImportBatch {
  var values: [BrowserCookieKey: HTTPCookie] = [:]
  for cookie in cookies {
    values[BrowserCookieKey(cookie)] = cookie
  }
  let sorted = values.values.sorted {
    ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name)
  }
  return BrowserImportBatch(cookies: sorted, skipped: skipped + cookies.count - sorted.count)
}
