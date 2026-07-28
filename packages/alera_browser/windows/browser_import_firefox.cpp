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

std::set<std::string> TableColumns(sqlite3* database) {
  sqlite3_stmt* raw = nullptr;
  if (sqlite3_prepare_v2(
          database, "PRAGMA table_info(moz_cookies)", -1, &raw,
          nullptr) != SQLITE_OK) {
    return {};
  }
  Statement statement(raw, sqlite3_finalize);
  (void)statement;
  std::set<std::string> columns;
  while (sqlite3_step(raw) == SQLITE_ROW) {
    const auto name = SqliteText(raw, 1);
    if (name.has_value()) {
      columns.insert(*name);
    }
  }
  return columns;
}

BrowserImportBatch ReadDatabase(
    const std::filesystem::path& source) {
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
  for (const auto* required : {
           "host", "name", "value", "path", "expiry", "isSecure",
           "isHttpOnly"}) {
    if (columns.count(required) == 0) {
      batch.outcome = "failed";
      batch.detail_code = "cookie_database_schema_unsupported";
      return batch;
    }
  }
  const auto same_site =
      columns.count("sameSite") != 0 ? "sameSite" : "0";
  const auto origin_attributes =
      columns.count("originAttributes") != 0
          ? "originAttributes"
          : "''";
  const std::string query =
      "SELECT host,name,value,path,expiry,isSecure,isHttpOnly," +
      std::string(same_site) + "," + origin_attributes +
      " FROM moz_cookies ORDER BY host,path,name";
  sqlite3_stmt* raw_statement = nullptr;
  if (sqlite3_prepare_v2(
          raw_database, query.c_str(), -1, &raw_statement,
          nullptr) != SQLITE_OK) {
    batch.outcome = "failed";
    batch.detail_code = "cookie_database_query_failed";
    return batch;
  }
  Statement statement(raw_statement, sqlite3_finalize);
  (void)statement;
  const double now = std::chrono::duration<double>(
                         std::chrono::system_clock::now()
                             .time_since_epoch())
                         .count();
  int step = SQLITE_ROW;
  while ((step = sqlite3_step(raw_statement)) == SQLITE_ROW) {
    const auto domain = SqliteText(raw_statement, 0);
    const auto name = SqliteText(raw_statement, 1);
    const auto value = SqliteText(raw_statement, 2);
    const auto path_value = SqliteText(raw_statement, 3);
    if (!domain.has_value() || domain->empty() || !name.has_value() ||
        name->empty() || !value.has_value() ||
        !path_value.has_value()) {
      batch.outcome = "failed";
      batch.detail_code = "cookie_database_invalid_row";
      return batch;
    }
    const auto origin_attribute_value = SqliteText(raw_statement, 8);
    if (origin_attribute_value.has_value() &&
        !origin_attribute_value->empty()) {
      ++batch.skipped;
      continue;
    }
    const int64_t expiry =
        sqlite3_column_int64(raw_statement, 4);
    if (expiry > 0 && static_cast<double>(expiry) <= now) {
      ++batch.skipped;
      continue;
    }
    BrowserCookieData cookie;
    cookie.domain = *domain;
    cookie.name = *name;
    cookie.value = *value;
    cookie.path = path_value->empty() ? "/" : *path_value;
    cookie.secure = sqlite3_column_int(raw_statement, 5) != 0;
    cookie.http_only = sqlite3_column_int(raw_statement, 6) != 0;
    cookie.session = expiry <= 0;
    if (expiry > 0) {
      cookie.expires_unix_seconds = static_cast<double>(expiry);
    }
    switch (sqlite3_column_int(raw_statement, 7)) {
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

BrowserImportBatch LoadFirefoxBrowserCookies(
    const BrowserImportLocation& location) {
  BrowserImportBatch combined;
  for (const auto& database : location.databases) {
    auto batch = ReadDatabase(database);
    if (!batch.succeeded()) {
      return batch;
    }
    combined.skipped += batch.skipped;
    combined.cookies.insert(
        combined.cookies.end(),
        std::make_move_iterator(batch.cookies.begin()),
        std::make_move_iterator(batch.cookies.end()));
  }
  return DeduplicateBrowserImportBatch(std::move(combined));
}

}  // namespace alera_browser
