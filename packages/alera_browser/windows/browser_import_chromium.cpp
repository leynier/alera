#include "browser_import_internal.h"

#include "browser_value.h"

#include <winsqlite/winsqlite3.h>

#include <chrono>
#include <iterator>
#include <memory>
#include <set>

namespace alera_browser {
namespace {

using Database = std::unique_ptr<sqlite3, decltype(&sqlite3_close)>;
using Statement = std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)>;

std::optional<std::string> SqliteText(
    sqlite3_stmt* statement,
    int column) {
  if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
    return std::nullopt;
  }
  const auto* value = sqlite3_column_text(statement, column);
  const int size = sqlite3_column_bytes(statement, column);
  if (value == nullptr || size < 0) {
    return std::nullopt;
  }
  return std::string(
      reinterpret_cast<const char*>(value),
      static_cast<size_t>(size));
}

std::vector<uint8_t> SqliteBlob(
    sqlite3_stmt* statement,
    int column) {
  const auto* value = static_cast<const uint8_t*>(
      sqlite3_column_blob(statement, column));
  const int size = sqlite3_column_bytes(statement, column);
  return value == nullptr || size <= 0
             ? std::vector<uint8_t>()
             : std::vector<uint8_t>(value, value + size);
}

std::set<std::string> TableColumns(sqlite3* database) {
  sqlite3_stmt* raw = nullptr;
  if (sqlite3_prepare_v2(
          database, "PRAGMA table_info(cookies)", -1, &raw,
          nullptr) != SQLITE_OK) {
    return {};
  }
  Statement statement(raw, sqlite3_finalize);
  std::set<std::string> columns;
  while (sqlite3_step(raw) == SQLITE_ROW) {
    const auto name = SqliteText(raw, 1);
    if (name.has_value()) {
      columns.insert(*name);
    }
  }
  return columns;
}

int MetadataVersion(sqlite3* database) {
  sqlite3_stmt* raw = nullptr;
  if (sqlite3_prepare_v2(
          database,
          "SELECT value FROM meta WHERE key = 'version' LIMIT 1",
          -1, &raw, nullptr) != SQLITE_OK) {
    return 0;
  }
  Statement statement(raw, sqlite3_finalize);
  if (sqlite3_step(raw) != SQLITE_ROW) {
    return 0;
  }
  const auto value = SqliteText(raw, 0);
  if (!value.has_value()) {
    return 0;
  }
  try {
    return std::stoi(*value);
  } catch (...) {
    return 0;
  }
}

bool RequiredColumnsPresent(const std::set<std::string>& columns) {
  for (const auto* column : {
           "host_key", "name", "value", "encrypted_value", "path",
           "expires_utc"}) {
    if (columns.count(column) == 0) {
      return false;
    }
  }
  return (columns.count("is_secure") != 0 ||
          columns.count("secure") != 0) &&
         (columns.count("is_httponly") != 0 ||
          columns.count("httponly") != 0);
}

std::string CookieQuery(const std::set<std::string>& columns) {
  const auto secure =
      columns.count("is_secure") != 0 ? "is_secure" : "secure";
  const auto http_only =
      columns.count("is_httponly") != 0 ? "is_httponly" : "httponly";
  const auto same_site =
      columns.count("samesite") != 0 ? "samesite" : "-1";
  std::string persistent;
  if (columns.count("is_persistent") != 0) {
    persistent = "is_persistent";
  } else if (columns.count("has_expires") != 0) {
    persistent = "has_expires";
  } else {
    persistent = "CASE WHEN expires_utc = 0 THEN 0 ELSE 1 END";
  }
  return std::string(
             "SELECT host_key,name,value,encrypted_value,path,"
             "expires_utc,") +
         secure + "," + http_only + "," + same_site + "," + persistent +
         " FROM cookies ORDER BY host_key,path,name";
}

BrowserImportBatch ReadDatabase(
    const std::filesystem::path& source,
    const std::vector<uint8_t>& key,
    const std::string& key_detail) {
  BrowserImportBatch batch;
  auto copy = BrowserDatabaseCopy::Create(source);
  if (!copy.has_value()) {
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_unreadable";
    return batch;
  }
  sqlite3* raw_database = nullptr;
  const auto path = Utf8(copy->path().wstring());
  if (sqlite3_open_v2(
          path.c_str(), &raw_database, SQLITE_OPEN_READONLY, nullptr) !=
      SQLITE_OK) {
    if (raw_database != nullptr) {
      sqlite3_close(raw_database);
    }
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_invalid";
    return batch;
  }
  Database database(raw_database, sqlite3_close);
  (void)database;
  sqlite3_busy_timeout(raw_database, 500);
  const auto columns = TableColumns(raw_database);
  if (!RequiredColumnsPresent(columns)) {
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_schema_unsupported";
    return batch;
  }
  sqlite3_stmt* raw_statement = nullptr;
  const auto query = CookieQuery(columns);
  if (sqlite3_prepare_v2(
          raw_database, query.c_str(), -1, &raw_statement,
          nullptr) != SQLITE_OK) {
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_query_failed";
    return batch;
  }
  Statement statement(raw_statement, sqlite3_finalize);
  (void)statement;
  const bool has_domain_digest = MetadataVersion(raw_database) >= 24;
  const double now = std::chrono::duration<double>(
                         std::chrono::system_clock::now()
                             .time_since_epoch())
                         .count();
  int step = SQLITE_ROW;
  while ((step = sqlite3_step(raw_statement)) == SQLITE_ROW) {
    const auto domain = SqliteText(raw_statement, 0);
    const auto name = SqliteText(raw_statement, 1);
    const auto plain = SqliteText(raw_statement, 2).value_or("");
    const auto encrypted = SqliteBlob(raw_statement, 3);
    const auto path_value = SqliteText(raw_statement, 4);
    if (!domain.has_value() || domain->empty() || !name.has_value() ||
        name->empty() || !path_value.has_value()) {
      batch.outcome = "failed";
      batch.detail_code = "cookie_database_invalid_row";
      return batch;
    }
    std::string cookie_value = plain;
    if (plain.empty() && !encrypted.empty()) {
      std::string detail;
      const auto decrypted = DecryptChromiumCookie(
          encrypted, key, has_domain_digest, *domain, &detail);
      if (!decrypted.has_value()) {
        batch.outcome =
            detail == "cookie_app_bound_encryption" ||
                    detail == "cookie_key_access_denied"
                ? "denied"
                : "failed";
        batch.detail_code =
            detail == "cookie_key_unavailable" && !key_detail.empty()
                ? key_detail
                : detail;
        return batch;
      }
      cookie_value = *decrypted;
    }
    const int64_t expires_raw =
        sqlite3_column_int64(raw_statement, 5);
    const bool persistent =
        sqlite3_column_int(raw_statement, 9) != 0 && expires_raw > 0;
    const double expires =
        (static_cast<double>(expires_raw) -
         11644473600000000.0) /
        1000000.0;
    if (persistent && expires <= now) {
      ++batch.skipped;
      continue;
    }
    BrowserCookieData cookie;
    cookie.domain = *domain;
    cookie.name = *name;
    cookie.value = std::move(cookie_value);
    cookie.path = path_value->empty() ? "/" : *path_value;
    cookie.secure = sqlite3_column_int(raw_statement, 6) != 0;
    cookie.http_only = sqlite3_column_int(raw_statement, 7) != 0;
    cookie.session = !persistent;
    if (persistent) {
      cookie.expires_unix_seconds = expires;
    }
    switch (sqlite3_column_int(raw_statement, 8)) {
      case 1:
        cookie.same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX;
        break;
      case 2:
        cookie.same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_STRICT;
        break;
      default:
        cookie.same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE;
    }
    batch.cookies.push_back(std::move(cookie));
    if (batch.cookies.size() > 100000) {
      batch.cookies.clear();
      batch.outcome = "failed";
      batch.detail_code = "cookie_database_too_many_cookies";
      return batch;
    }
  }
  if (step != SQLITE_DONE) {
    batch.cookies.clear();
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_query_failed";
  }
  return batch;
}

}  // namespace

BrowserImportBatch LoadChromiumBrowserCookies(
    const BrowserImportLocation& location) {
  BrowserImportBatch combined;
  std::string key_detail;
  auto loaded_key =
      LoadChromiumEncryptionKey(location.local_state, &key_detail);
  std::vector<uint8_t> key =
      loaded_key.has_value() ? std::move(*loaded_key)
                             : std::vector<uint8_t>();
  for (const auto& database : location.databases) {
    auto batch = ReadDatabase(database, key, key_detail);
    if (!batch.succeeded()) {
      SecureZeroMemory(key.data(), key.size());
      return batch;
    }
    combined.skipped += batch.skipped;
    combined.cookies.insert(
        combined.cookies.end(),
        std::make_move_iterator(batch.cookies.begin()),
        std::make_move_iterator(batch.cookies.end()));
  }
  SecureZeroMemory(key.data(), key.size());
  return DeduplicateBrowserImportBatch(std::move(combined));
}

}  // namespace alera_browser
