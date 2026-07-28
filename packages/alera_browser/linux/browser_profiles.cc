#include "browser_state.h"

#include <glib/gstdio.h>

namespace {

GQuark profile_error_quark() {
  return g_quark_from_static_string("alera-browser-profile-error");
}

gboolean valid_profile_id(const gchar* id) {
  if (id == nullptr) {
    return FALSE;
  }
  const gsize length = strlen(id);
  if (length == 0 || length > 64 || strstr(id, "..") != nullptr) {
    return FALSE;
  }
  for (const gchar* cursor = id; *cursor != '\0'; cursor++) {
    if (!g_ascii_isalnum(*cursor) && *cursor != '-' && *cursor != '_' &&
        *cursor != '.') {
      return FALSE;
    }
  }
  return TRUE;
}

gboolean remove_file_tree(GFile* file, GError** error) {
  GFileType type = g_file_query_file_type(
      file, G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr);
  if (type == G_FILE_TYPE_DIRECTORY) {
    g_autoptr(GFileEnumerator) enumerator = g_file_enumerate_children(
        file, G_FILE_ATTRIBUTE_STANDARD_NAME,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, error);
    if (enumerator == nullptr) {
      return FALSE;
    }
    while (true) {
      g_autoptr(GFileInfo) info =
          g_file_enumerator_next_file(enumerator, nullptr, error);
      if (info == nullptr) {
        return error == nullptr || *error == nullptr
                   ? g_file_delete(file, nullptr, error)
                   : FALSE;
      }
      g_autoptr(GFile) child = g_file_get_child(
          file, g_file_info_get_name(info));
      if (!remove_file_tree(child, error)) {
        return FALSE;
      }
    }
  }
  return g_file_delete(file, nullptr, error);
}

}  // namespace

LinuxBrowserProfile* browser_profile_create(AleraBrowserPlugin* plugin,
                                            const gchar* id,
                                            gboolean ephemeral,
                                            GError** error) {
  if (!valid_profile_id(id)) {
    g_set_error(error, profile_error_quark(), 1,
                "Profile id must use 1-64 safe ASCII characters.");
    return nullptr;
  }

  LinuxBrowserProfile* profile = g_new0(LinuxBrowserProfile, 1);
  profile->id = g_strdup(id);
  profile->ephemeral = ephemeral;
  if (ephemeral) {
    profile->data_manager = webkit_website_data_manager_new_ephemeral();
    profile->context =
        webkit_web_context_new_with_website_data_manager(profile->data_manager);
  } else {
    profile->root_path = g_build_filename(plugin->profile_root, id, nullptr);
    g_autofree gchar* data_path =
        g_build_filename(profile->root_path, "data", nullptr);
    g_autofree gchar* cache_path =
        g_build_filename(profile->root_path, "cache", nullptr);
    if (g_mkdir_with_parents(data_path, 0700) != 0 ||
        g_mkdir_with_parents(cache_path, 0700) != 0) {
      g_set_error(error, profile_error_quark(), 2,
                  "Could not create the isolated profile directories.");
      browser_profile_destroy(profile);
      return nullptr;
    }
    profile->data_manager = webkit_website_data_manager_new(
        "base-data-directory", data_path, "base-cache-directory", cache_path,
        nullptr);
    profile->context =
        webkit_web_context_new_with_website_data_manager(profile->data_manager);
  }
  webkit_website_data_manager_set_tls_errors_policy(
      profile->data_manager, WEBKIT_TLS_ERRORS_POLICY_FAIL);
  browser_profile_connect_signals(plugin, profile);
  return profile;
}

void browser_profile_destroy(gpointer data) {
  LinuxBrowserProfile* profile = static_cast<LinuxBrowserProfile*>(data);
  if (profile == nullptr) {
    return;
  }
  g_clear_object(&profile->context);
  g_clear_object(&profile->data_manager);
  g_clear_pointer(&profile->root_path, g_free);
  g_clear_pointer(&profile->id, g_free);
  g_free(profile);
}

FlValue* browser_profile_value(LinuxBrowserProfile* profile) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "id", fl_value_new_string(profile->id));
  fl_value_set_string_take(
      value, "storage",
      fl_value_new_string(profile->ephemeral ? "ephemeral" : "persistent"));
  fl_value_set_string_take(
      value, "isDefault",
      fl_value_new_bool(g_strcmp0(profile->id, "default") == 0));
  return value;
}

gboolean browser_profile_remove_storage(LinuxBrowserProfile* profile,
                                        GError** error) {
  if (profile->ephemeral || profile->root_path == nullptr ||
      !g_file_test(profile->root_path, G_FILE_TEST_EXISTS)) {
    return TRUE;
  }
  g_autoptr(GFile) root = g_file_new_for_path(profile->root_path);
  return remove_file_tree(root, error);
}
