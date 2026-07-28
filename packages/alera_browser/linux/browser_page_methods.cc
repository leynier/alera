#include "browser_state.h"

#include <libsoup/soup.h>

#include <cmath>
#include <cstring>

namespace {

LinuxBrowserPage* lookup_page(AleraBrowserPlugin* plugin, FlValue* args) {
  const gchar* id = browser_map_string(args, "pageId");
  return id != nullptr
             ? static_cast<LinuxBrowserPage*>(
                   g_hash_table_lookup(plugin->pages, id))
             : nullptr;
}

void respond_missing_page(FlMethodCall* call) {
  browser_respond(
      call, browser_error("page_not_found",
                          "The browser page does not exist."));
}

gboolean valid_browser_url(const gchar* value) {
  if (g_strcmp0(value, "about:blank") == 0) {
    return TRUE;
  }
  if (value == nullptr) {
    return FALSE;
  }
  g_autoptr(GUri) uri =
      g_uri_parse(value, G_URI_FLAGS_NONE, nullptr);
  const gchar* scheme = uri != nullptr ? g_uri_get_scheme(uri) : nullptr;
  const gchar* host = uri != nullptr ? g_uri_get_host(uri) : nullptr;
  return host != nullptr && *host != '\0' &&
         (g_strcmp0(scheme, "http") == 0 ||
          g_strcmp0(scheme, "https") == 0);
}

gboolean set_upload_paths(LinuxBrowserPage* page,
                          FlValue* values,
                          GError** error) {
  if (values == nullptr || fl_value_get_type(values) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(values) == 0) {
    g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_INVAL,
                        "At least one upload file is required.");
    return FALSE;
  }
  g_ptr_array_set_size(page->pending_upload_paths, 0);
  for (size_t index = 0; index < fl_value_get_length(values); index++) {
    FlValue* value = fl_value_get_list_value(values, index);
    if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
      g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_INVAL,
                          "Every upload path must be a string.");
      return FALSE;
    }
    const gchar* path = fl_value_get_string(value);
    if (!g_path_is_absolute(path) ||
        !g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
      g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_NOENT,
                          "An upload file is missing or not regular.");
      return FALSE;
    }
    g_ptr_array_add(page->pending_upload_paths, g_strdup(path));
  }
  return TRUE;
}

}  // namespace

void browser_page_handle_method(AleraBrowserPlugin* plugin,
                                FlMethodCall* method_call,
                                const gchar* method,
                                FlValue* args) {
  if (std::strcmp(method, "page.create") == 0) {
    const gchar* profile_id = browser_map_string(args, "profileId");
    LinuxBrowserProfile* profile = static_cast<LinuxBrowserProfile*>(
        g_hash_table_lookup(plugin->profiles,
                            profile_id != nullptr ? profile_id : "default"));
    if (profile == nullptr) {
      browser_respond(
          method_call,
          browser_error("profile_not_found",
                        "The browser profile does not exist."));
      return;
    }
    const gchar* requested_id = browser_map_string(args, "id");
    g_autofree gchar* generated_id =
        requested_id == nullptr
            ? g_strdup_printf("page-%" G_GUINT64_FORMAT,
                              plugin->next_page_id++)
            : nullptr;
    const gchar* id =
        requested_id != nullptr ? requested_id : generated_id;
    const gchar* opener_id = browser_map_string(args, "openerPageId");
    LinuxBrowserPage* opener =
        opener_id != nullptr
            ? static_cast<LinuxBrowserPage*>(
                  g_hash_table_lookup(plugin->pages, opener_id))
            : nullptr;
    if (opener_id != nullptr && opener == nullptr) {
      respond_missing_page(method_call);
      return;
    }
    GError* error = nullptr;
    LinuxBrowserPage* page = browser_page_create(
        plugin, id, profile, opener,
        browser_map_bool(args, "transient", FALSE), &error);
    if (page == nullptr) {
      browser_respond(
          method_call,
          browser_error("page_create_failed",
                        error != nullptr ? error->message
                                         : "Page creation failed."));
      g_clear_error(&error);
      return;
    }
    g_hash_table_insert(plugin->pages, g_strdup(page->id), page);
    const gchar* user_agent = browser_map_string(args, "userAgent");
    if (user_agent != nullptr) {
      webkit_settings_set_user_agent(
          webkit_web_view_get_settings(page->web_view), user_agent);
    }
    const gchar* initial_url = browser_map_string(args, "initialUrl");
    if (initial_url != nullptr && !valid_browser_url(initial_url)) {
      g_autofree gchar* page_id = g_strdup(page->id);
      g_hash_table_remove(plugin->pages, page_id);
      browser_respond(
          method_call,
          browser_error(
              "unsupported_url",
              "Only HTTP, HTTPS, and about:blank are supported."));
      return;
    }
    if (initial_url != nullptr) {
      webkit_web_view_load_uri(page->web_view, initial_url);
    }
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(
        result, "id", fl_value_new_string(page->id));
    browser_respond(method_call, browser_success(result));
    return;
  }

  LinuxBrowserPage* page = lookup_page(plugin, args);
  if (page == nullptr) {
    if (std::strcmp(method, "page.close") == 0) {
      browser_respond(method_call, browser_success());
    } else {
      respond_missing_page(method_call);
    }
    return;
  }

  if (std::strcmp(method, "page.attach") == 0 ||
      std::strcmp(method, "page.detach") == 0) {
    page->attached = std::strcmp(method, "page.attach") == 0;
    browser_page_update_visibility(page);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.setObscured") == 0) {
    page->obscured = browser_map_bool(args, "obscured", FALSE);
    browser_page_update_visibility(page);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.setBounds") == 0) {
    page->frame_x = std::lround(browser_map_double(args, "x", 0));
    page->frame_y = std::lround(browser_map_double(args, "y", 0));
    page->frame_width =
        std::lround(browser_map_double(args, "width", 0));
    page->frame_height =
        std::lround(browser_map_double(args, "height", 0));
    browser_page_update_visibility(page);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.adoptTransient") == 0) {
    const gchar* profile_id = browser_map_string(args, "profileId");
    if (!page->transient ||
        g_strcmp0(page->profile_id, profile_id) != 0) {
      browser_respond(
          method_call,
          browser_error("invalid_transient_page",
                        "The transient popup profile does not match."));
      return;
    }
    page->adopted = TRUE;
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.promoteTransient") == 0) {
    if (!page->transient || !page->adopted) {
      browser_respond(
          method_call,
          browser_error("invalid_transient_page",
                        "The transient popup was not adopted."));
      return;
    }
    page->transient = FALSE;
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.close") == 0) {
    g_autofree gchar* page_id = g_strdup(page->id);
    g_hash_table_remove(plugin->pages, page_id);
    browser_update_flutter_input_region(plugin);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.currentUrl") == 0) {
    const gchar* uri = webkit_web_view_get_uri(page->web_view);
    browser_respond(
        method_call,
        browser_success(uri != nullptr ? fl_value_new_string(uri)
                                       : fl_value_new_null()));
  } else if (std::strcmp(method, "page.title") == 0) {
    const gchar* title = webkit_web_view_get_title(page->web_view);
    browser_respond(
        method_call,
        browser_success(title != nullptr ? fl_value_new_string(title)
                                         : fl_value_new_null()));
  } else if (std::strcmp(method, "page.canGoBack") == 0) {
    browser_respond(
        method_call,
        browser_success(fl_value_new_bool(
            webkit_web_view_can_go_back(page->web_view))));
  } else if (std::strcmp(method, "page.canGoForward") == 0) {
    browser_respond(
        method_call,
        browser_success(fl_value_new_bool(
            webkit_web_view_can_go_forward(page->web_view))));
  } else if (std::strcmp(method, "page.goBack") == 0) {
    webkit_web_view_go_back(page->web_view);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.goForward") == 0) {
    webkit_web_view_go_forward(page->web_view);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.reload") == 0) {
    webkit_web_view_reload(page->web_view);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.stop") == 0) {
    webkit_web_view_stop_loading(page->web_view);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.loadUrl") == 0) {
    const gchar* url = browser_map_string(args, "url");
    if (!valid_browser_url(url)) {
      browser_respond(
          method_call, browser_error(
                           "unsupported_url",
                           "Only HTTP, HTTPS, and about:blank are supported."));
      return;
    }
    WebKitURIRequest* request = webkit_uri_request_new(url);
    SoupMessageHeaders* headers =
        webkit_uri_request_get_http_headers(request);
    FlValue* requested_headers = browser_map_lookup(args, "headers");
    if (requested_headers != nullptr &&
        fl_value_get_type(requested_headers) == FL_VALUE_TYPE_MAP) {
      for (size_t index = 0;
           index < fl_value_get_length(requested_headers); index++) {
        FlValue* key = fl_value_get_map_key(requested_headers, index);
        FlValue* value = fl_value_get_map_value(requested_headers, index);
        if (fl_value_get_type(key) == FL_VALUE_TYPE_STRING &&
            fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
          soup_message_headers_replace(
              headers, fl_value_get_string(key), fl_value_get_string(value));
        }
      }
    }
    webkit_web_view_load_request(page->web_view, request);
    g_object_unref(request);
    browser_respond(method_call, browser_success());
  } else if (std::strcmp(method, "page.evaluateJavaScript") == 0) {
    browser_evaluate_javascript(
        page->web_view, browser_map_string(args, "script"), method_call);
  } else if (std::strcmp(method, "page.upload") == 0) {
    GError* error = nullptr;
    if (!set_upload_paths(
            page, browser_map_lookup(args, "filePaths"), &error)) {
      browser_respond(
          method_call,
          browser_error("invalid_upload",
                        error != nullptr ? error->message
                                         : "Upload paths are invalid."));
      g_clear_error(&error);
      return;
    }
    const gchar* element_ref =
        browser_map_string(args, "elementRef");
    g_autofree gchar* escaped = g_strescape(
        element_ref != nullptr ? element_ref : "", nullptr);
    g_autofree gchar* script = g_strdup_printf(
        "window.__aleraBrowserAutomation?.elements?.get(\"%s\")"
        "?.element?.click(); true;",
        escaped);
    browser_evaluate_javascript(page->web_view, script, method_call);
  } else {
    browser_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
  }
}
