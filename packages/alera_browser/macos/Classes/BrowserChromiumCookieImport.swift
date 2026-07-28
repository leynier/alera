import CommonCrypto
import Foundation
import LocalAuthentication
import SQLite3
import Security

enum BrowserChromiumCookieImport {
  static func load(
    source: ChromiumImportSource,
    profile: BrowserImportProfileLocation
  ) throws -> BrowserImportBatch {
    let key = try safeStorageKey(labels: source.keychainLabels)
    return try read(database: profile.fileURL, key: key)
  }

  private static func read(database: URL, key: Data) throws -> BrowserImportBatch {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("alera-browser-import-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let copy = temporaryDirectory.appendingPathComponent("Cookies")
      try FileManager.default.copyItem(at: database, to: copy)
      for suffix in ["-wal", "-shm"] {
        let source = URL(fileURLWithPath: database.path + suffix)
        if FileManager.default.fileExists(atPath: source.path) {
          try? FileManager.default.copyItem(
            at: source,
            to: URL(fileURLWithPath: copy.path + suffix)
          )
        }
      }
      defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
      return try queryDatabase(copy, key: key)
    } catch let error as BrowserImportError {
      throw error
    } catch {
      try? FileManager.default.removeItem(at: temporaryDirectory)
      throw BrowserImportError("failed", "cookie_database_unreadable")
    }
  }

  private static func queryDatabase(_ url: URL, key: Data) throws -> BrowserImportBatch {
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
    let columns = tableColumns(database, table: "cookies")
    let required = ["host_key", "name", "value", "encrypted_value", "path", "expires_utc"]
    guard required.allSatisfy(columns.contains) else {
      throw BrowserImportError("failed", "cookie_database_schema_unsupported")
    }
    let secure = columns.contains("is_secure") ? "is_secure" : "secure"
    let httpOnly = columns.contains("is_httponly") ? "is_httponly" : "httponly"
    guard columns.contains(secure), columns.contains(httpOnly) else {
      throw BrowserImportError("failed", "cookie_database_schema_unsupported")
    }
    let sameSite = columns.contains("samesite") ? "samesite" : "-1"
    let hasExpires =
      columns.contains("has_expires")
      ? "has_expires"
      : "CASE WHEN expires_utc = 0 THEN 0 ELSE 1 END"
    let sql = """
      SELECT host_key, name, value, encrypted_value, path, expires_utc,
             \(secure), \(httpOnly), \(sameSite), \(hasExpires)
      FROM cookies
      ORDER BY host_key, path, name
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw BrowserImportError("failed", "cookie_database_query_failed")
    }
    defer { sqlite3_finalize(statement) }
    let metadataVersion = chromiumMetadataVersion(database)
    var cookies: [HTTPCookie] = []
    var skipped = 0
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let domain = sqliteText(statement, 0),
        let name = sqliteText(statement, 1),
        let path = sqliteText(statement, 4)
      else {
        throw BrowserImportError("failed", "cookie_database_invalid_row")
      }
      let plain = sqliteText(statement, 2) ?? ""
      let encrypted = sqliteBlob(statement, 3) ?? Data()
      let cookieValue: String
      if !plain.isEmpty || encrypted.isEmpty {
        cookieValue = plain
      } else {
        cookieValue = try decrypt(
          encrypted,
          key: key,
          hasDomainDigest: metadataVersion >= 24,
          domain: domain
        )
      }
      let expiresRaw = sqlite3_column_int64(statement, 5)
      let persistent = sqlite3_column_int(statement, 9) != 0 && expiresRaw > 0
      let expires = persistent ? chromiumDate(expiresRaw) : nil
      if let expires, expires <= Date() {
        skipped += 1
        continue
      }
      let sameSiteValue: String
      switch sqlite3_column_int(statement, 8) {
      case 1:
        sameSiteValue = "lax"
      case 2:
        sameSiteValue = "strict"
      default:
        sameSiteValue = "none"
      }
      var map: [String: Any] = [
        "name": name,
        "value": cookieValue,
        "domain": domain,
        "path": path.isEmpty ? "/" : path,
        "secure": sqlite3_column_int(statement, 6) != 0,
        "httpOnly": sqlite3_column_int(statement, 7) != 0,
        "sameSite": sameSiteValue,
        "session": !persistent,
      ]
      if let expires {
        map["expiresUtc"] = Int64(expires.timeIntervalSince1970 * 1000)
      }
      do {
        cookies.append(try decodeBrowserCookie(map))
      } catch {
        throw BrowserImportError("failed", "cookie_database_invalid_row")
      }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
      throw BrowserImportError("failed", "cookie_database_query_failed")
    }
    return BrowserImportBatch(cookies: cookies, skipped: skipped)
  }

  private static func safeStorageKey(
    labels: [(service: String, account: String)]
  ) throws -> Data {
    var interactionLabel: (service: String, account: String)?
    for label in labels {
      let lookup = keychainPassword(label: label, allowInteraction: false)
      if let password = lookup.password {
        return try deriveKey(password)
      }
      if lookup.status == errSecInteractionNotAllowed, interactionLabel == nil {
        interactionLabel = label
      }
    }
    guard let interactionLabel else {
      throw BrowserImportError("unavailable", "keychain_item_not_found")
    }
    let lookup = keychainPassword(label: interactionLabel, allowInteraction: true)
    guard let password = lookup.password else {
      let denied =
        lookup.status == errSecUserCanceled
        || lookup.status == errSecAuthFailed
        || lookup.status == errSecInteractionNotAllowed
      throw BrowserImportError(denied ? "denied" : "failed", "keychain_access_failed")
    }
    return try deriveKey(password)
  }

  private static func keychainPassword(
    label: (service: String, account: String),
    allowInteraction: Bool
  ) -> (status: OSStatus, password: String?) {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: label.service,
      kSecAttrAccount as String: label.account,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]
    if !allowInteraction {
      let context = LAContext()
      context.interactionNotAllowed = true
      query[kSecUseAuthenticationContext as String] = context
    }
    var raw: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &raw)
    guard
      status == errSecSuccess,
      let data = raw as? Data,
      let password = String(data: data, encoding: .utf8)
    else {
      return (status, nil)
    }
    return (status, password)
  }

  private static func deriveKey(_ password: String) throws -> Data {
    let salt = Data("saltysalt".utf8)
    let passwordBytes = Array(password.utf8)
    var key = Data(count: kCCKeySizeAES128)
    let keyLength = key.count
    let status = key.withUnsafeMutableBytes { keyBytes in
      salt.withUnsafeBytes { saltBytes in
        passwordBytes.withUnsafeBytes { passwordBuffer in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBuffer.bindMemory(to: Int8.self).baseAddress,
            passwordBytes.count,
            saltBytes.bindMemory(to: UInt8.self).baseAddress,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            keyBytes.bindMemory(to: UInt8.self).baseAddress,
            keyLength
          )
        }
      }
    }
    guard status == kCCSuccess else {
      throw BrowserImportError("failed", "cookie_key_derivation_failed")
    }
    return key
  }

  private static func decrypt(
    _ encrypted: Data,
    key: Data,
    hasDomainDigest: Bool,
    domain: String
  ) throws -> String {
    guard encrypted.count > 3, String(data: encrypted.prefix(3), encoding: .utf8) == "v10" else {
      throw BrowserImportError("failed", "cookie_encryption_unsupported")
    }
    let payload = Data(encrypted.dropFirst(3))
    let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
    var output = Data(count: payload.count + kCCBlockSizeAES128)
    var outputCount = 0
    let capacity = output.count
    let status = output.withUnsafeMutableBytes { outputBytes in
      payload.withUnsafeBytes { payloadBytes in
        key.withUnsafeBytes { keyBytes in
          iv.withUnsafeBytes { ivBytes in
            CCCrypt(
              CCOperation(kCCDecrypt),
              CCAlgorithm(kCCAlgorithmAES),
              CCOptions(kCCOptionPKCS7Padding),
              keyBytes.baseAddress,
              key.count,
              ivBytes.baseAddress,
              payloadBytes.baseAddress,
              payload.count,
              outputBytes.baseAddress,
              capacity,
              &outputCount
            )
          }
        }
      }
    }
    guard status == kCCSuccess else {
      throw BrowserImportError("failed", "cookie_decryption_failed")
    }
    output.count = outputCount
    if hasDomainDigest {
      guard output.count >= 32 else {
        throw BrowserImportError("failed", "cookie_decryption_failed")
      }
      var expected = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
      let domainData = Data(domain.utf8)
      domainData.withUnsafeBytes { bytes in
        _ = CC_SHA256(bytes.baseAddress, CC_LONG(domainData.count), &expected)
      }
      guard Data(output.prefix(32)) == Data(expected) else {
        throw BrowserImportError("failed", "cookie_decryption_failed")
      }
      output.removeFirst(32)
    }
    guard let value = String(data: output, encoding: .utf8) else {
      throw BrowserImportError("failed", "cookie_decryption_failed")
    }
    return value
  }
}

private func tableColumns(_ database: OpaquePointer, table: String) -> Set<String> {
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil)
      == SQLITE_OK
  else {
    return []
  }
  defer { sqlite3_finalize(statement) }
  var values = Set<String>()
  while sqlite3_step(statement) == SQLITE_ROW {
    if let name = sqliteText(statement, 1) { values.insert(name) }
  }
  return values
}

private func chromiumMetadataVersion(_ database: OpaquePointer) -> Int {
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT value FROM meta WHERE key = 'version' LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    return 0
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqliteText(statement, 0) else {
    return 0
  }
  return Int(raw) ?? 0
}

private func sqliteText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
  guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
  guard let value = sqlite3_column_text(statement, index) else { return nil }
  return String(cString: value)
}

private func sqliteBlob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
  guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
  let count = Int(sqlite3_column_bytes(statement, index))
  guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
    return Data()
  }
  return Data(bytes: bytes, count: count)
}

private func chromiumDate(_ value: Int64) -> Date {
  Date(timeIntervalSince1970: TimeInterval(value - 11_644_473_600_000_000) / 1_000_000)
}
