#ifndef ALERA_BROWSER_LINUX_BROWSER_IMPORT_INTERNAL_H_
#define ALERA_BROWSER_LINUX_BROWSER_IMPORT_INTERNAL_H_

#include <glib.h>
#include <libsoup/soup.h>

struct BrowserCookieImportBatch {
  GList* cookies;
  guint imported_count;
  guint skipped_count;
  gboolean unavailable;
  gchar* detail_code;
};

struct BrowserCookieImportProfile {
  gchar* name;
  gchar* database_path;
};

BrowserCookieImportBatch* browser_cookie_import_batch_new();
void browser_cookie_import_batch_free(BrowserCookieImportBatch* batch);
GPtrArray* browser_cookie_import_find_profiles(const gchar* source);
const BrowserCookieImportProfile* browser_cookie_import_select_profile(
    GPtrArray* profiles,
    const gchar* selected_name,
    gchar** detail_code);
BrowserCookieImportBatch* browser_cookie_import_read_chromium(
    const gchar* source,
    const gchar* database_path);
BrowserCookieImportBatch* browser_cookie_import_read_firefox(
    const gchar* database_path);
BrowserCookieImportBatch* browser_cookie_import_parse_json(const gchar* json);

#endif
