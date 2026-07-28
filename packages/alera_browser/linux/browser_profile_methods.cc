#include "browser_state.h"

#include <cstring>

namespace {

gboolean profile_has_pages(AleraBrowserPlugin* plugin,
                           const gchar* profile_id) {
  GHashTableIter iterator;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iterator, plugin->pages);
  while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
    LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(value);
    if (g_strcmp0(page->profile_id, profile_id) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

}  // namespace

void browser_profile_handle_method(AleraBrowserPlugin* plugin,
                                   FlMethodCall* method_call,
                                   const gchar* method,
                                   FlValue* args) {
  if (std::strcmp(method, "profile.list") == 0) {
    g_autoptr(FlValue) profiles = fl_value_new_list();
    GHashTableIter iterator;
    gpointer value = nullptr;
    g_hash_table_iter_init(&iterator, plugin->profiles);
    while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
      fl_value_append_take(
          profiles,
          browser_profile_value(static_cast<LinuxBrowserProfile*>(value)));
    }
    browser_respond(method_call, browser_success(profiles));
    return;
  }

  const gchar* profile_id =
      std::strcmp(method, "profile.create") == 0
          ? browser_map_string(args, "id")
          : browser_map_string(args, "profileId");
  if (profile_id == nullptr || *profile_id == '\0') {
    browser_respond(
        method_call,
        browser_error("invalid_profile", "A profile id is required."));
    return;
  }

  if (std::strcmp(method, "profile.create") == 0) {
    if (g_hash_table_contains(plugin->profiles, profile_id)) {
      browser_respond(
          method_call,
          browser_error("duplicate_profile",
                        "The browser profile already exists."));
      return;
    }
    const gchar* storage = browser_map_string(args, "storage");
    const gboolean ephemeral = g_strcmp0(storage, "ephemeral") == 0;
    GError* error = nullptr;
    LinuxBrowserProfile* profile =
        browser_profile_create(plugin, profile_id, ephemeral, &error);
    if (profile == nullptr) {
      browser_respond(
          method_call,
          browser_error("profile_create_failed",
                        error != nullptr ? error->message
                                         : "Profile creation failed."));
      g_clear_error(&error);
      return;
    }
    g_hash_table_insert(plugin->profiles, g_strdup(profile->id), profile);
    g_autoptr(FlValue) value = browser_profile_value(profile);
    browser_respond(method_call, browser_success(value));
    return;
  }

  if (std::strcmp(method, "profile.delete") == 0) {
    LinuxBrowserProfile* profile = static_cast<LinuxBrowserProfile*>(
        g_hash_table_lookup(plugin->profiles, profile_id));
    if (profile == nullptr) {
      browser_respond(
          method_call,
          browser_error("profile_not_found",
                        "The browser profile does not exist."));
      return;
    }
    if (g_str_equal(profile_id, "default")) {
      browser_respond(
          method_call,
          browser_error("default_profile",
                        "The default profile cannot be deleted."));
      return;
    }
    if (profile_has_pages(plugin, profile_id)) {
      browser_respond(
          method_call,
          browser_error("profile_in_use",
                        "Close every profile page before deleting it."));
      return;
    }
    gpointer stolen_key = nullptr;
    gpointer stolen_profile = nullptr;
    g_hash_table_steal_extended(
        plugin->profiles, profile_id, &stolen_key, &stolen_profile);
    g_free(stolen_key);
    profile = static_cast<LinuxBrowserProfile*>(stolen_profile);
    g_clear_object(&profile->context);
    g_clear_object(&profile->data_manager);
    GError* error = nullptr;
    const gboolean removed =
        browser_profile_remove_storage(profile, &error);
    if (!removed) {
      GError* restore_error = nullptr;
      LinuxBrowserProfile* restored = browser_profile_create(
          plugin, profile_id, FALSE, &restore_error);
      if (restored != nullptr) {
        g_hash_table_insert(
            plugin->profiles, g_strdup(profile_id), restored);
      } else {
        g_warning("Failed to restore browser profile %s: %s", profile_id,
                  restore_error != nullptr ? restore_error->message
                                           : "unknown error");
      }
      g_clear_error(&restore_error);
      browser_profile_destroy(profile);
      browser_respond(
          method_call,
          browser_error("profile_delete_failed",
                        error != nullptr ? error->message
                                         : "Profile deletion failed."));
      g_clear_error(&error);
      return;
    }
    browser_profile_destroy(profile);
    browser_respond(method_call, browser_success());
  }
}
