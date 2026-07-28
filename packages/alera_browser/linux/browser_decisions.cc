#include "browser_state.h"

namespace {

void deny_decision(LinuxBrowserDecision* decision) {
  switch (decision->kind) {
    case LINUX_BROWSER_DECISION_PERMISSION:
      webkit_permission_request_deny(
          WEBKIT_PERMISSION_REQUEST(decision->native_request));
      break;
    case LINUX_BROWSER_DECISION_DOWNLOAD:
      webkit_download_cancel(WEBKIT_DOWNLOAD(decision->native_request));
      break;
    case LINUX_BROWSER_DECISION_POPUP:
      if (decision->transient_page_id != nullptr) {
        g_hash_table_remove(
            decision->plugin->pages, decision->transient_page_id);
        browser_update_flutter_input_region(decision->plugin);
      }
      break;
  }
}

gboolean decision_timeout_cb(gpointer user_data) {
  LinuxBrowserDecision* decision =
      static_cast<LinuxBrowserDecision*>(user_data);
  decision->timeout_id = 0;
  g_autofree gchar* id = g_strdup(decision->id);
  deny_decision(decision);
  g_hash_table_remove(decision->plugin->decisions, id);
  return G_SOURCE_REMOVE;
}

gboolean valid_destination_path(const gchar* path) {
  if (path == nullptr || !g_path_is_absolute(path) ||
      g_file_test(path, G_FILE_TEST_EXISTS)) {
    return FALSE;
  }
  g_autofree gchar* parent = g_path_get_dirname(path);
  return g_file_test(parent, G_FILE_TEST_IS_DIR);
}

}  // namespace

LinuxBrowserDecision* browser_decision_create(
    AleraBrowserPlugin* plugin,
    LinuxBrowserDecisionKind kind,
    LinuxBrowserPage* page) {
  LinuxBrowserDecision* decision = g_new0(LinuxBrowserDecision, 1);
  decision->plugin = plugin;
  decision->kind = kind;
  decision->page_id = g_strdup(page->id);
  decision->id =
      g_strdup_printf("d%" G_GUINT64_FORMAT, plugin->next_decision_id++);
  decision->timeout_id =
      g_timeout_add_seconds(30, decision_timeout_cb, decision);
  g_hash_table_insert(
      plugin->decisions, g_strdup(decision->id), decision);
  return decision;
}

void browser_decision_destroy(gpointer data) {
  LinuxBrowserDecision* decision =
      static_cast<LinuxBrowserDecision*>(data);
  if (decision == nullptr) {
    return;
  }
  if (decision->timeout_id != 0) {
    g_source_remove(decision->timeout_id);
  }
  g_clear_object(&decision->native_request);
  g_clear_pointer(&decision->id, g_free);
  g_clear_pointer(&decision->page_id, g_free);
  g_clear_pointer(&decision->transient_page_id, g_free);
  g_free(decision);
}

void browser_decision_resolve(AleraBrowserPlugin* plugin,
                              FlMethodCall* method_call,
                              FlValue* args) {
  const gchar* decision_id = browser_map_string(args, "decisionId");
  const gchar* action = browser_map_string(args, "decision");
  LinuxBrowserDecision* decision = decision_id != nullptr
                                       ? static_cast<LinuxBrowserDecision*>(
                                             g_hash_table_lookup(
                                                 plugin->decisions, decision_id))
                                       : nullptr;
  if (decision == nullptr || action == nullptr) {
    browser_respond(
        method_call,
        browser_error("decision_not_found",
                      "The native browser decision expired or is unknown."));
    return;
  }

  gboolean accepted = FALSE;
  switch (decision->kind) {
    case LINUX_BROWSER_DECISION_PERMISSION:
      accepted = g_str_equal(action, "allow");
      if (accepted) {
        webkit_permission_request_allow(
            WEBKIT_PERMISSION_REQUEST(decision->native_request));
      } else {
        webkit_permission_request_deny(
            WEBKIT_PERMISSION_REQUEST(decision->native_request));
      }
      break;
    case LINUX_BROWSER_DECISION_POPUP: {
      const gchar* target_page_id =
          browser_map_string(args, "targetPageId");
      LinuxBrowserPage* transient_page =
          decision->transient_page_id != nullptr
              ? static_cast<LinuxBrowserPage*>(g_hash_table_lookup(
                    plugin->pages, decision->transient_page_id))
              : nullptr;
      accepted = g_str_equal(action, "newPage") &&
                 decision->trusted &&
                 target_page_id != nullptr &&
                 g_strcmp0(target_page_id,
                           decision->transient_page_id) == 0 &&
                 transient_page != nullptr && transient_page->adopted;
      if (!accepted && decision->transient_page_id != nullptr) {
        g_hash_table_remove(plugin->pages,
                            decision->transient_page_id);
        browser_update_flutter_input_region(plugin);
      }
      break;
    }
    case LINUX_BROWSER_DECISION_DOWNLOAD: {
      const gchar* destination =
          browser_map_string(args, "destinationPath");
      accepted = g_str_equal(action, "accept") &&
                 valid_destination_path(destination);
      if (accepted) {
        g_autofree gchar* uri =
            g_filename_to_uri(destination, nullptr, nullptr);
        if (uri != nullptr) {
          webkit_download_set_allow_overwrite(
              WEBKIT_DOWNLOAD(decision->native_request), FALSE);
          webkit_download_set_destination(
              WEBKIT_DOWNLOAD(decision->native_request), uri);
        } else {
          accepted = FALSE;
        }
      }
      if (!accepted) {
        webkit_download_cancel(
            WEBKIT_DOWNLOAD(decision->native_request));
      }
      break;
    }
  }

  g_hash_table_remove(plugin->decisions, decision_id);
  browser_respond(method_call, browser_success());
}
