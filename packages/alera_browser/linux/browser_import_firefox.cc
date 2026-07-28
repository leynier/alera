#include "browser_import_internal.h"

#include <sqlite3.h>

namespace {

SoupCookie* cookie_from_row(sqlite3_stmt* statement) {
  const gchar* origin_attributes = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 0));
  const gchar* name = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 1));
  const gchar* value = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 2));
  const gchar* domain = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 3));
  const gchar* path = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 4));
  if ((origin_attributes != nullptr && *origin_attributes != '\0') ||
      name == nullptr || *name == '\0' || value == nullptr ||
      domain == nullptr || *domain == '\0' || path == nullptr ||
      *path != '/' || !g_utf8_validate(value, -1, nullptr)) {
    return nullptr;
  }
  SoupCookie* cookie = soup_cookie_new(name, value, domain, path, -1);
  if (cookie == nullptr) {
    return nullptr;
  }
  soup_cookie_set_secure(cookie, sqlite3_column_int(statement, 6) != 0);
  soup_cookie_set_http_only(cookie, sqlite3_column_int(statement, 7) != 0);
  const gint same_site = sqlite3_column_int(statement, 8);
  soup_cookie_set_same_site_policy(
      cookie, same_site == 1 ? SOUP_SAME_SITE_POLICY_LAX
                             : same_site == 2
                                   ? SOUP_SAME_SITE_POLICY_STRICT
                                   : SOUP_SAME_SITE_POLICY_NONE);
  const gint64 expiry = sqlite3_column_int64(statement, 5);
  if (expiry > 0) {
    g_autoptr(GDateTime) expires =
        g_date_time_new_from_unix_utc(expiry);
    if (expires != nullptr) {
      soup_cookie_set_expires(cookie, expires);
    }
  }
  return cookie;
}

}  // namespace

BrowserCookieImportBatch* browser_cookie_import_read_firefox(
    const gchar* database_path) {
  BrowserCookieImportBatch* batch = browser_cookie_import_batch_new();
  sqlite3* database = nullptr;
  if (sqlite3_open_v2(database_path, &database,
                      SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                      nullptr) != SQLITE_OK) {
    sqlite3_close(database);
    batch->detail_code = g_strdup("source_read_failed");
    return batch;
  }
  sqlite3_busy_timeout(database, 500);
  sqlite3_exec(database, "PRAGMA query_only=ON", nullptr, nullptr, nullptr);
  sqlite3_stmt* statement = nullptr;
  const gchar* query =
      "SELECT originAttributes,name,value,host,path,expiry,isSecure,"
      "isHttpOnly,sameSite FROM moz_cookies";
  if (sqlite3_prepare_v2(database, query, -1, &statement, nullptr) !=
      SQLITE_OK) {
    sqlite3_close(database);
    batch->detail_code = g_strdup("source_schema_unsupported");
    return batch;
  }
  while (batch->imported_count + batch->skipped_count < 100000) {
    const gint step = sqlite3_step(statement);
    if (step == SQLITE_DONE) {
      break;
    }
    if (step != SQLITE_ROW) {
      batch->detail_code = g_strdup("source_read_failed");
      break;
    }
    SoupCookie* cookie = cookie_from_row(statement);
    if (cookie == nullptr) {
      batch->skipped_count++;
    } else {
      batch->cookies = g_list_prepend(batch->cookies, cookie);
      batch->imported_count++;
    }
  }
  if (batch->imported_count + batch->skipped_count == 100000 &&
      batch->detail_code == nullptr) {
    batch->detail_code = g_strdup("source_cookie_limit");
  }
  sqlite3_finalize(statement);
  sqlite3_close(database);
  batch->cookies = g_list_reverse(batch->cookies);
  return batch;
}
