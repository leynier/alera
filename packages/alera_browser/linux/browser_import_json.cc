#include "browser_import_internal.h"

#include <json-glib/json-glib.h>

#include <cmath>
#include <cstring>

namespace {

const gchar* optional_string(JsonObject* object, const gchar* key) {
  if (!json_object_has_member(object, key)) {
    return nullptr;
  }
  JsonNode* node = json_object_get_member(object, key);
  return node != nullptr && JSON_NODE_HOLDS_VALUE(node) &&
                 json_node_get_value_type(node) == G_TYPE_STRING
             ? json_node_get_string(node)
             : nullptr;
}

gboolean optional_bool(JsonObject* object,
                       const gchar* key,
                       gboolean fallback) {
  if (!json_object_has_member(object, key)) {
    return fallback;
  }
  JsonNode* node = json_object_get_member(object, key);
  return node != nullptr && JSON_NODE_HOLDS_VALUE(node) &&
                 json_node_get_value_type(node) == G_TYPE_BOOLEAN
             ? json_node_get_boolean(node)
             : fallback;
}

gboolean optional_number(JsonObject* object,
                         const gchar* key,
                         double* result) {
  if (!json_object_has_member(object, key)) {
    return FALSE;
  }
  JsonNode* node = json_object_get_member(object, key);
  if (node == nullptr || !JSON_NODE_HOLDS_VALUE(node)) {
    return FALSE;
  }
  const GType type = json_node_get_value_type(node);
  if (type != G_TYPE_DOUBLE && type != G_TYPE_INT64 &&
      type != G_TYPE_INT && type != G_TYPE_UINT64 &&
      type != G_TYPE_UINT) {
    return FALSE;
  }
  *result = json_node_get_double(node);
  return std::isfinite(*result);
}

SoupCookie* parse_cookie(JsonObject* object) {
  const gchar* name = optional_string(object, "name");
  const gchar* value = optional_string(object, "value");
  const gchar* domain = optional_string(object, "domain");
  const gchar* path = optional_string(object, "path");
  if (name == nullptr || *name == '\0' || value == nullptr ||
      domain == nullptr || *domain == '\0') {
    return nullptr;
  }
  if (path == nullptr) {
    path = "/";
  }
  if (*path != '/') {
    return nullptr;
  }
  SoupCookie* cookie = soup_cookie_new(name, value, domain, path, -1);
  if (cookie == nullptr) {
    return nullptr;
  }
  soup_cookie_set_secure(
      cookie, optional_bool(object, "secure", FALSE));
  soup_cookie_set_http_only(
      cookie,
      optional_bool(object, "httpOnly",
                    optional_bool(object, "http_only", FALSE)));
  const gchar* same_site = optional_string(object, "sameSite");
  if (g_strcmp0(same_site, "lax") == 0) {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_LAX);
  } else if (g_strcmp0(same_site, "strict") == 0) {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_STRICT);
  } else {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_NONE);
  }
  if (!optional_bool(object, "session", FALSE)) {
    double expiration = 0;
    gboolean milliseconds =
        optional_number(object, "expiresUtc", &expiration);
    if (!milliseconds) {
      optional_number(object, "expirationDate", &expiration);
    }
    if (expiration > 0) {
      const gint64 seconds = static_cast<gint64>(
          milliseconds ? expiration / 1000 : expiration);
      g_autoptr(GDateTime) expires =
          g_date_time_new_from_unix_utc(seconds);
      if (expires == nullptr) {
        soup_cookie_free(cookie);
        return nullptr;
      }
      soup_cookie_set_expires(cookie, expires);
    }
  }
  return cookie;
}

JsonArray* cookie_array(JsonNode* root) {
  if (root == nullptr) {
    return nullptr;
  }
  if (JSON_NODE_HOLDS_ARRAY(root)) {
    return json_node_get_array(root);
  }
  if (!JSON_NODE_HOLDS_OBJECT(root)) {
    return nullptr;
  }
  JsonObject* object = json_node_get_object(root);
  if (!json_object_has_member(object, "cookies")) {
    return nullptr;
  }
  JsonNode* cookies = json_object_get_member(object, "cookies");
  return cookies != nullptr && JSON_NODE_HOLDS_ARRAY(cookies)
             ? json_node_get_array(cookies)
             : nullptr;
}

}  // namespace

BrowserCookieImportBatch* browser_cookie_import_parse_json(const gchar* json) {
  BrowserCookieImportBatch* batch = browser_cookie_import_batch_new();
  if (json == nullptr) {
    batch->detail_code = g_strdup("manual_json_invalid");
    return batch;
  }
  if (strlen(json) > 16 * 1024 * 1024) {
    batch->detail_code = g_strdup("manual_json_too_large");
    return batch;
  }
  g_autoptr(JsonParser) parser = json_parser_new();
  GError* error = nullptr;
  if (!json_parser_load_from_data(parser, json, -1, &error)) {
    batch->detail_code = g_strdup("invalid_json");
    g_clear_error(&error);
    return batch;
  }
  JsonArray* cookies = cookie_array(json_parser_get_root(parser));
  if (cookies == nullptr || json_array_get_length(cookies) > 100000) {
    batch->detail_code =
        g_strdup(
            cookies == nullptr ? "invalid_cookie_array"
                               : "manual_json_too_many_cookies");
    return batch;
  }
  for (guint index = 0; index < json_array_get_length(cookies); index++) {
    JsonNode* node = json_array_get_element(cookies, index);
    if (node == nullptr || !JSON_NODE_HOLDS_OBJECT(node)) {
      batch->skipped_count++;
      continue;
    }
    SoupCookie* cookie = parse_cookie(json_node_get_object(node));
    if (cookie == nullptr) {
      batch->skipped_count++;
      continue;
    }
    batch->cookies = g_list_prepend(batch->cookies, cookie);
    batch->imported_count++;
  }
  batch->cookies = g_list_reverse(batch->cookies);
  return batch;
}
