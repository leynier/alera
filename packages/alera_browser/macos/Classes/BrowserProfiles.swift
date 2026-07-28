import FlutterMacOS
import WebKit

final class BrowserProfile {
  let id: String
  let storage: String
  let isDefault: Bool
  let dataStore: WKWebsiteDataStore
  let persistentIdentifier: UUID?

  init(id: String, storage: String, isDefault: Bool) {
    self.id = id
    self.storage = storage
    self.isDefault = isDefault
    if storage == "ephemeral" {
      dataStore = .nonPersistent()
      persistentIdentifier = nil
    } else {
      let identifier = stableProfileUUID(id)
      dataStore = WKWebsiteDataStore(forIdentifier: identifier)
      persistentIdentifier = identifier
    }
  }

  var value: [String: Any] {
    ["id": id, "storage": storage, "isDefault": isDefault]
  }
}

extension AleraBrowserPlugin {
  private static var profileDefaultsKey: String {
    "dev.leynier.alera.browser.profiles.v1"
  }

  func installStoredProfiles() {
    profiles["default"] = BrowserProfile(
      id: "default",
      storage: "persistent",
      isDefault: true
    )
    let values =
      UserDefaults.standard.array(forKey: Self.profileDefaultsKey)
      as? [[String: String]] ?? []
    for value in values {
      guard
        let id = value["id"],
        id != "default",
        (try? validateIdentifier(id, kind: "profile")) != nil
      else {
        continue
      }
      profiles[id] = BrowserProfile(
        id: id,
        storage: "persistent",
        isDefault: false
      )
    }
  }

  func handleProfileMethod(
    _ method: String,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    switch method {
    case "profile.create":
      let id = try arguments.requiredString("id")
      try validateIdentifier(id, kind: "profile")
      guard profiles[id] == nil else {
        throw BrowserMethodError("duplicate_profile", "The browser profile already exists.")
      }
      let storage = arguments.optionalString("storage") ?? "persistent"
      guard storage == "persistent" || storage == "ephemeral" else {
        throw BrowserMethodError("invalid_profile_storage", "The profile storage mode is invalid.")
      }
      let profile = BrowserProfile(id: id, storage: storage, isDefault: id == "default")
      profiles[id] = profile
      persistProfiles()
      result(profile.value)
    case "profile.list":
      result(profiles.values.sorted { $0.id < $1.id }.map(\.value))
    case "profile.delete":
      let id = try arguments.requiredString("profileId")
      try deleteProfile(id, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func deleteProfile(_ id: String, result: @escaping FlutterResult) throws {
    guard id != "default" else {
      throw BrowserMethodError("default_profile", "The default browser profile cannot be deleted.")
    }
    guard let profile = profiles[id] else {
      throw BrowserMethodError("profile_not_found", "The browser profile does not exist.")
    }
    guard !activeCookieImports.contains(id) else {
      throw BrowserMethodError(
        "import_in_progress",
        "The browser profile cannot be deleted while cookies are importing."
      )
    }
    guard !pages.values.contains(where: { $0.profile.id == id }) else {
      throw BrowserMethodError(
        "profile_in_use",
        "Close every page that uses this browser profile before deleting it."
      )
    }
    profiles.removeValue(forKey: id)
    persistProfiles()
    guard let identifier = profile.persistentIdentifier else {
      result(nil)
      return
    }
    WKWebsiteDataStore.remove(forIdentifier: identifier) { [weak self] error in
      if let error {
        self?.profiles[id] = profile
        self?.persistProfiles()
        result(
          BrowserMethodError("profile_delete_failed", error.localizedDescription)
            .asFlutterError
        )
      } else {
        result(nil)
      }
    }
  }

  private func persistProfiles() {
    let values = profiles.values
      .filter { !$0.isDefault && $0.storage == "persistent" }
      .sorted { $0.id < $1.id }
      .map { ["id": $0.id] }
    UserDefaults.standard.set(values, forKey: Self.profileDefaultsKey)
  }

  func profile(_ id: String) throws -> BrowserProfile {
    guard let profile = profiles[id] else {
      throw BrowserMethodError("profile_not_found", "The browser profile does not exist.")
    }
    return profile
  }
}
