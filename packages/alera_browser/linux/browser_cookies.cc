#include "browser_state.h"

#include <libsoup/soup.h>

#include <cstring>

namespace {

struct CookieCall {
  FlMethodCall* call;
  GList* cookies;
  guint affected;
};

CookieCall* cookie_call_new(FlMethodCall* call) {
  CookieCall* context = g_new0(CookieCall, 1);
  context->call = FL_METHOD_CALL(g_object_ref(call));
  return context;
}

void cookie_call_free(CookieCall* context) {
  if (context == nullptr) {
    return;
  }
  g_clear_object(&context->call);
  g_list_free_full(
      context->cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  g_free(context);
}

LinuxBrowserProfile* lookup_profile(AleraBrowserPlugin* plugin,
                                    FlMethodCall* call,
                                    FlValue* args) {
  const gchar* profile_id = browser_map_string(args, "profileId");
  LinuxBrowserProfile* profile =
      profile_id != nullptr
          ? static_cast<LinuxBrowserProfile*>(
                g_hash_table_lookup(plugin->profiles, profile_id))
          : nullptr;
  if (profile == nullptr) {
    browser_respond(
        call, browser_error("profile_not_found",
                            "The browser profile does not exist."));
  }
  return profile;
}

FlValue* cookie_value(SoupCookie* cookie) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(
      value, "name", fl_value_new_string(soup_cookie_get_name(cookie)));
  fl_value_set_string_take(
      value, "value", fl_value_new_string(soup_cookie_get_value(cookie)));
  fl_value_set_string_take(
      value, "domain", fl_value_new_string(soup_cookie_get_domain(cookie)));
  fl_value_set_string_take(
      value, "path", fl_value_new_string(soup_cookie_get_path(cookie)));
  GDateTime* expires = soup_cookie_get_expires(cookie);
  if (expires != nullptr) {
    fl_value_set_string_take(
        value, "expiresUtc",
        fl_value_new_int(g_date_time_to_unix(expires) * 1000));
  }
  fl_value_set_string_take(
      value, "secure",
      fl_value_new_bool(soup_cookie_get_secure(cookie)));
  fl_value_set_string_take(
      value, "httpOnly",
      fl_value_new_bool(soup_cookie_get_http_only(cookie)));
  const gchar* same_site = nullptr;
  switch (soup_cookie_get_same_site_policy(cookie)) {
    case SOUP_SAME_SITE_POLICY_NONE:
      same_site = "none";
      break;
    case SOUP_SAME_SITE_POLICY_LAX:
      same_site = "lax";
      break;
    case SOUP_SAME_SITE_POLICY_STRICT:
      same_site = "strict";
      break;
  }
  fl_value_set_string_take(
      value, "sameSite", fl_value_new_string(same_site));
  fl_value_set_string_take(
      value, "session", fl_value_new_bool(expires == nullptr));
  return value;
}

SoupCookie* decode_cookie(FlValue* value, GError** error) {
  const gchar* name = browser_map_string(value, "name");
  const gchar* raw_value = browser_map_string(value, "value");
  const gchar* domain = browser_map_string(value, "domain");
  const gchar* path = browser_map_string(value, "path");
  if (name == nullptr || *name == '\0' || raw_value == nullptr ||
      domain == nullptr || *domain == '\0' || path == nullptr ||
      *path != '/') {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "Cookie name, value, domain, and absolute path are "
                        "required.");
    return nullptr;
  }
  SoupCookie* cookie = soup_cookie_new(name, raw_value, domain, path, -1);
  if (cookie == nullptr) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "The cookie is invalid.");
    return nullptr;
  }
  FlValue* expires_value = browser_map_lookup(value, "expiresUtc");
  if (expires_value != nullptr &&
      fl_value_get_type(expires_value) == FL_VALUE_TYPE_INT) {
    g_autoptr(GDateTime) expires = g_date_time_new_from_unix_utc(
        fl_value_get_int(expires_value) / 1000);
    if (expires == nullptr) {
      soup_cookie_free(cookie);
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                          "The cookie expiration is invalid.");
      return nullptr;
    }
    soup_cookie_set_expires(cookie, expires);
  }
  soup_cookie_set_secure(
      cookie, browser_map_bool(value, "secure", FALSE));
  soup_cookie_set_http_only(
      cookie, browser_map_bool(value, "httpOnly", FALSE));
  const gchar* same_site = browser_map_string(value, "sameSite");
  if (g_strcmp0(same_site, "lax") == 0) {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_LAX);
  } else if (g_strcmp0(same_site, "strict") == 0) {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_STRICT);
  } else {
    soup_cookie_set_same_site_policy(cookie, SOUP_SAME_SITE_POLICY_NONE);
  }
  return cookie;
}

void get_cookies_done(GObject* object,
                      GAsyncResult* result,
                      gpointer user_data) {
  CookieCall* context = static_cast<CookieCall*>(user_data);
  GError* error = nullptr;
  context->cookies = webkit_cookie_manager_get_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (error != nullptr) {
    browser_respond(
        context->call, browser_error("cookie_read_failed", error->message));
    g_clear_error(&error);
    cookie_call_free(context);
    return;
  }
  g_autoptr(FlValue) values = fl_value_new_list();
  for (GList* item = context->cookies; item != nullptr; item = item->next) {
    fl_value_append_take(
        values, cookie_value(static_cast<SoupCookie*>(item->data)));
  }
  browser_respond(context->call, browser_success(values));
  cookie_call_free(context);
}

void add_cookie_done(GObject* object,
                     GAsyncResult* result,
                     gpointer user_data) {
  CookieCall* context = static_cast<CookieCall*>(user_data);
  GError* error = nullptr;
  const gboolean added = webkit_cookie_manager_add_cookie_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (!added) {
    browser_respond(
        context->call,
        browser_error("cookie_write_failed",
                      error != nullptr ? error->message
                                       : "The cookie was not written."));
  } else {
    browser_respond(context->call, browser_success());
  }
  g_clear_error(&error);
  cookie_call_free(context);
}

gboolean cookie_matches(SoupCookie* cookie, FlValue* filter) {
  const gchar* name = browser_map_string(filter, "name");
  const gchar* domain = browser_map_string(filter, "domain");
  const gchar* path = browser_map_string(filter, "path");
  const gchar* url = browser_map_string(filter, "url");
  if (name != nullptr && g_strcmp0(name, soup_cookie_get_name(cookie)) != 0) {
    return FALSE;
  }
  if (domain != nullptr &&
      g_strcmp0(domain, soup_cookie_get_domain(cookie)) != 0) {
    return FALSE;
  }
  if (path != nullptr && g_strcmp0(path, soup_cookie_get_path(cookie)) != 0) {
    return FALSE;
  }
  if (url != nullptr) {
    g_autoptr(GUri) uri = g_uri_parse(url, G_URI_FLAGS_NONE, nullptr);
    if (uri == nullptr || !soup_cookie_applies_to_uri(cookie, uri)) {
      return FALSE;
    }
  }
  return TRUE;
}

void replace_cookies_done(GObject* object,
                          GAsyncResult* result,
                          gpointer user_data) {
  CookieCall* context = static_cast<CookieCall*>(user_data);
  GError* error = nullptr;
  const gboolean replaced = webkit_cookie_manager_replace_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (!replaced) {
    browser_respond(
        context->call,
        browser_error("cookie_delete_failed",
                      error != nullptr ? error->message
                                       : "Cookies were not deleted."));
  } else {
    browser_respond(
        context->call,
        browser_success(fl_value_new_int(context->affected)));
  }
  g_clear_error(&error);
  cookie_call_free(context);
}

void get_all_for_delete_done(GObject* object,
                             GAsyncResult* result,
                             gpointer user_data) {
  CookieCall* context = static_cast<CookieCall*>(user_data);
  WebKitCookieManager* manager = WEBKIT_COOKIE_MANAGER(object);
  GError* error = nullptr;
  GList* existing =
      webkit_cookie_manager_get_all_cookies_finish(manager, result, &error);
  if (error != nullptr) {
    browser_respond(
        context->call, browser_error("cookie_read_failed", error->message));
    g_clear_error(&error);
    cookie_call_free(context);
    return;
  }
  FlValue* filter = fl_method_call_get_args(context->call);
  for (GList* item = existing; item != nullptr; item = item->next) {
    SoupCookie* cookie = static_cast<SoupCookie*>(item->data);
    if (cookie_matches(cookie, filter)) {
      context->affected++;
    } else {
      context->cookies =
          g_list_prepend(context->cookies, soup_cookie_copy(cookie));
    }
  }
  context->cookies = g_list_reverse(context->cookies);
  g_list_free_full(
      existing, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  webkit_cookie_manager_replace_cookies(
      manager, context->cookies, nullptr, replace_cookies_done, context);
}

}  // namespace

void browser_cookie_handle_method(AleraBrowserPlugin* plugin,
                                  FlMethodCall* method_call,
                                  const gchar* method,
                                  FlValue* args) {
  LinuxBrowserProfile* profile =
      lookup_profile(plugin, method_call, args);
  if (profile == nullptr) {
    return;
  }
  WebKitCookieManager* manager =
      webkit_web_context_get_cookie_manager(profile->context);
  if (std::strcmp(method, "cookies.get") == 0) {
    const gchar* url = browser_map_string(args, "url");
    if (url == nullptr) {
      browser_respond(
          method_call, browser_error("invalid_url", "A URL is required."));
      return;
    }
    CookieCall* context = cookie_call_new(method_call);
    webkit_cookie_manager_get_cookies(
        manager, url, nullptr, get_cookies_done, context);
  } else if (std::strcmp(method, "cookies.set") == 0) {
    GError* error = nullptr;
    SoupCookie* cookie =
        decode_cookie(browser_map_lookup(args, "cookie"), &error);
    if (cookie == nullptr) {
      browser_respond(
          method_call,
          browser_error("invalid_cookie",
                        error != nullptr ? error->message
                                         : "The cookie is invalid."));
      g_clear_error(&error);
      return;
    }
    CookieCall* context = cookie_call_new(method_call);
    context->cookies = g_list_append(nullptr, cookie);
    webkit_cookie_manager_add_cookie(
        manager, cookie, nullptr, add_cookie_done, context);
  } else if (std::strcmp(method, "cookies.delete") == 0) {
    CookieCall* context = cookie_call_new(method_call);
    webkit_cookie_manager_get_all_cookies(
        manager, nullptr, get_all_for_delete_done, context);
  } else {
    browser_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
  }
}
