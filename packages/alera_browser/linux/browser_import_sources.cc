#include "browser_import_internal.h"
#include "browser_import_profile_selection.h"

#include <glib/gstdio.h>
#include <json-glib/json-glib.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

void browser_cookie_import_profile_free(
    BrowserCookieImportProfile* profile) {
  if (profile == nullptr) {
    return;
  }
  g_clear_pointer(&profile->name, g_free);
  g_clear_pointer(&profile->database_path, g_free);
  g_free(profile);
}

gint compare_profiles(gconstpointer first, gconstpointer second) {
  const auto* first_profile =
      *static_cast<BrowserCookieImportProfile* const*>(first);
  const auto* second_profile =
      *static_cast<BrowserCookieImportProfile* const*>(second);
  const gint by_name =
      g_strcmp0(first_profile->name, second_profile->name);
  return by_name != 0
             ? by_name
             : g_strcmp0(
                   first_profile->database_path,
                   second_profile->database_path);
}

const gchar* chromium_config_directory(const gchar* source) {
  if (g_strcmp0(source, "chrome") == 0) {
    return "google-chrome";
  }
  if (g_strcmp0(source, "edge") == 0) {
    return "microsoft-edge";
  }
  if (g_strcmp0(source, "brave") == 0) {
    return "BraveSoftware/Brave-Browser";
  }
  return nullptr;
}

gboolean is_chromium_profile_directory(const gchar* name) {
  return g_strcmp0(name, "Default") == 0 ||
         g_str_has_prefix(name, "Profile ") ||
         g_str_has_prefix(name, "user-");
}

GHashTable* chromium_profile_display_names(const gchar* root) {
  GHashTable* names =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  g_autofree gchar* local_state =
      g_build_filename(root, "Local State", nullptr);
  GStatBuf metadata = {};
  if (g_stat(local_state, &metadata) != 0 ||
      metadata.st_size < 0 ||
      metadata.st_size > 16 * 1024 * 1024) {
    return names;
  }
  g_autofree gchar* contents = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(local_state, &contents, &length, nullptr)) {
    return names;
  }
  g_autoptr(JsonParser) parser = json_parser_new();
  if (!json_parser_load_from_data(
          parser, contents, static_cast<gssize>(length), nullptr)) {
    return names;
  }
  JsonNode* root_node = json_parser_get_root(parser);
  if (root_node == nullptr || !JSON_NODE_HOLDS_OBJECT(root_node)) {
    return names;
  }
  JsonNode* profile_node =
      json_object_get_member(
          json_node_get_object(root_node), "profile");
  if (profile_node == nullptr ||
      !JSON_NODE_HOLDS_OBJECT(profile_node)) {
    return names;
  }
  JsonNode* cache_node =
      json_object_get_member(
          json_node_get_object(profile_node), "info_cache");
  if (cache_node == nullptr || !JSON_NODE_HOLDS_OBJECT(cache_node)) {
    return names;
  }
  JsonObject* cache = json_node_get_object(cache_node);
  GList* directories = json_object_get_members(cache);
  for (GList* entry = directories; entry != nullptr; entry = entry->next) {
    const gchar* directory = static_cast<const gchar*>(entry->data);
    JsonNode* info_node = json_object_get_member(cache, directory);
    if (info_node == nullptr || !JSON_NODE_HOLDS_OBJECT(info_node)) {
      continue;
    }
    JsonNode* name_node =
        json_object_get_member(json_node_get_object(info_node), "name");
    if (name_node == nullptr || !JSON_NODE_HOLDS_VALUE(name_node) ||
        json_node_get_value_type(name_node) != G_TYPE_STRING) {
      continue;
    }
    const gchar* name = json_node_get_string(name_node);
    if (name != nullptr && *name != '\0') {
      g_hash_table_insert(
          names, g_strdup(directory), g_strdup(name));
    }
  }
  g_list_free(directories);
  return names;
}

gchar* chromium_cookie_path(
    const gchar* root,
    const gchar* profile_name) {
  g_autofree gchar* modern =
      g_build_filename(
          root, profile_name, "Network", "Cookies", nullptr);
  if (g_file_test(modern, G_FILE_TEST_IS_REGULAR)) {
    return g_steal_pointer(&modern);
  }
  g_autofree gchar* legacy =
      g_build_filename(root, profile_name, "Cookies", nullptr);
  return g_file_test(legacy, G_FILE_TEST_IS_REGULAR)
             ? g_steal_pointer(&legacy)
             : nullptr;
}

gboolean contains_database(
    GPtrArray* profiles,
    const gchar* database_path) {
  for (guint index = 0; index < profiles->len; ++index) {
    const auto* profile = static_cast<BrowserCookieImportProfile*>(
        g_ptr_array_index(profiles, index));
    if (g_strcmp0(profile->database_path, database_path) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

void add_profile(
    GPtrArray* profiles,
    const gchar* name,
    const gchar* database_path) {
  if (name == nullptr || *name == '\0' ||
      database_path == nullptr ||
      !g_file_test(database_path, G_FILE_TEST_IS_REGULAR) ||
      contains_database(profiles, database_path)) {
    return;
  }
  auto* profile = g_new0(BrowserCookieImportProfile, 1);
  profile->name = g_strdup(name);
  profile->database_path = g_strdup(database_path);
  g_ptr_array_add(profiles, profile);
}

GPtrArray* find_chromium_profiles(const gchar* source) {
  GPtrArray* profiles = g_ptr_array_new_with_free_func(
      reinterpret_cast<GDestroyNotify>(
          browser_cookie_import_profile_free));
  const gchar* relative_root = chromium_config_directory(source);
  if (relative_root == nullptr) {
    return profiles;
  }
  g_autofree gchar* root =
      g_build_filename(
          g_get_user_config_dir(), relative_root, nullptr);
  g_autoptr(GDir) directory = g_dir_open(root, 0, nullptr);
  if (directory == nullptr) {
    return profiles;
  }
  GHashTable* display_names = chromium_profile_display_names(root);
  const gchar* entry = nullptr;
  while ((entry = g_dir_read_name(directory)) != nullptr) {
    if (!is_chromium_profile_directory(entry)) {
      continue;
    }
    g_autofree gchar* database =
        chromium_cookie_path(root, entry);
    const auto* display_name = static_cast<const gchar*>(
        g_hash_table_lookup(display_names, entry));
    add_profile(
        profiles,
        display_name == nullptr ? entry : display_name,
        database);
  }
  g_hash_table_unref(display_names);
  g_ptr_array_sort(profiles, compare_profiles);
  return profiles;
}

void add_firefox_profile(
    GPtrArray* profiles,
    const gchar* profile_path) {
  if (profile_path == nullptr || *profile_path == '\0') {
    return;
  }
  g_autofree gchar* name = g_path_get_basename(profile_path);
  g_autofree gchar* database =
      g_build_filename(profile_path, "cookies.sqlite", nullptr);
  const gchar* separator = std::strchr(name, '.');
  const gchar* display_name =
      separator != nullptr && separator[1] != '\0'
          ? separator + 1
          : name;
  add_profile(profiles, display_name, database);
}

GPtrArray* find_firefox_profiles() {
  GPtrArray* profiles = g_ptr_array_new_with_free_func(
      reinterpret_cast<GDestroyNotify>(
          browser_cookie_import_profile_free));
  g_autofree gchar* root =
      g_build_filename(
          g_get_home_dir(), ".mozilla", "firefox", nullptr);
  g_autofree gchar* profiles_ini =
      g_build_filename(root, "profiles.ini", nullptr);
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  if (g_key_file_load_from_file(
          key_file, profiles_ini, G_KEY_FILE_NONE, nullptr)) {
    gsize group_count = 0;
    g_auto(GStrv) groups =
        g_key_file_get_groups(key_file, &group_count);
    for (gsize index = 0; index < group_count; ++index) {
      if (!g_str_has_prefix(groups[index], "Profile")) {
        continue;
      }
      g_autofree gchar* path =
          g_key_file_get_string(
              key_file, groups[index], "Path", nullptr);
      if (path == nullptr || *path == '\0') {
        continue;
      }
      const gboolean relative =
          g_key_file_get_integer(
              key_file, groups[index], "IsRelative", nullptr) != 0;
      g_autofree gchar* profile_path =
          relative ? g_build_filename(root, path, nullptr)
                   : g_strdup(path);
      add_firefox_profile(profiles, profile_path);
    }
  }
  g_autoptr(GDir) directory = g_dir_open(root, 0, nullptr);
  if (directory != nullptr) {
    const gchar* entry = nullptr;
    while ((entry = g_dir_read_name(directory)) != nullptr) {
      g_autofree gchar* profile_path =
          g_build_filename(root, entry, nullptr);
      add_firefox_profile(profiles, profile_path);
    }
  }
  g_ptr_array_sort(profiles, compare_profiles);
  return profiles;
}

}  // namespace

BrowserCookieImportBatch* browser_cookie_import_batch_new() {
  return g_new0(BrowserCookieImportBatch, 1);
}

void browser_cookie_import_batch_free(
    BrowserCookieImportBatch* batch) {
  if (batch == nullptr) {
    return;
  }
  g_list_free_full(
      batch->cookies,
      reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  g_clear_pointer(&batch->detail_code, g_free);
  g_free(batch);
}

GPtrArray* browser_cookie_import_find_profiles(const gchar* source) {
  if (g_strcmp0(source, "firefox") == 0) {
    return find_firefox_profiles();
  }
  return find_chromium_profiles(source);
}

const BrowserCookieImportProfile* browser_cookie_import_select_profile(
    GPtrArray* profiles,
    const gchar* selected_name,
    gchar** detail_code) {
  std::vector<std::string> names;
  if (profiles != nullptr) {
    names.reserve(profiles->len);
    for (guint index = 0; index < profiles->len; ++index) {
      const auto* profile = static_cast<BrowserCookieImportProfile*>(
          g_ptr_array_index(profiles, index));
      names.emplace_back(profile->name);
    }
  }
  size_t selected_index = 0;
  const auto selection = select_linux_browser_import_profile(
      names, selected_name == nullptr ? "" : selected_name,
      &selected_index);
  if (selection == LinuxBrowserImportProfileSelection::found) {
    return static_cast<BrowserCookieImportProfile*>(
        g_ptr_array_index(profiles, selected_index));
  }
  if (detail_code != nullptr) {
    *detail_code = g_strdup(
        selection == LinuxBrowserImportProfileSelection::ambiguous
            ? "source_profile_ambiguous"
            : selected_name == nullptr || *selected_name == '\0'
                  ? "source_profile_required"
                  : "source_profile_not_found");
  }
  return nullptr;
}
