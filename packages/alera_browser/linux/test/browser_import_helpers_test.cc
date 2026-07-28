#include "browser_import_internal.h"

#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>

namespace {

bool Expect(bool value, const char* message) {
  if (!value) {
    std::cerr << message << '\n';
  }
  return value;
}

bool SelectsOnlyAnExactUniqueProfile() {
  BrowserCookieImportProfile first{
      const_cast<gchar*>("Default"),
      const_cast<gchar*>("/one/Cookies")};
  BrowserCookieImportProfile second{
      const_cast<gchar*>("Profile 1"),
      const_cast<gchar*>("/two/Cookies")};
  BrowserCookieImportProfile duplicate{
      const_cast<gchar*>("Default"),
      const_cast<gchar*>("/three/Cookies")};
  g_autoptr(GPtrArray) profiles = g_ptr_array_new();
  g_ptr_array_add(profiles, &first);
  g_ptr_array_add(profiles, &second);
  g_ptr_array_add(profiles, &duplicate);

  g_autofree gchar* detail = nullptr;
  const auto* selected = browser_cookie_import_select_profile(
      profiles, "Profile 1", &detail);
  if (!Expect(
          selected == &second && detail == nullptr,
          "unique source profile was not selected")) {
    return false;
  }
  selected = browser_cookie_import_select_profile(
      profiles, "Missing", &detail);
  if (!Expect(
          selected == nullptr &&
              g_strcmp0(detail, "source_profile_not_found") == 0,
          "unknown source profile was accepted")) {
    return false;
  }
  g_clear_pointer(&detail, g_free);
  selected = browser_cookie_import_select_profile(
      profiles, "Default", &detail);
  return Expect(
      selected == nullptr &&
          g_strcmp0(detail, "source_profile_ambiguous") == 0,
      "ambiguous source profile was accepted");
}

bool RejectsOversizedManualJson() {
  std::string payload(16 * 1024 * 1024 + 1, ' ');
  BrowserCookieImportBatch* batch =
      browser_cookie_import_parse_json(payload.c_str());
  const bool rejected =
      batch != nullptr &&
      g_strcmp0(
          batch->detail_code, "manual_json_too_large") == 0;
  browser_cookie_import_batch_free(batch);
  return Expect(rejected, "oversized manual JSON was accepted");
}

bool RejectsTooManyManualCookies() {
  std::string payload = "[";
  for (int index = 0; index < 100001; ++index) {
    if (index != 0) {
      payload += ',';
    }
    payload += "{}";
  }
  payload += ']';
  BrowserCookieImportBatch* batch =
      browser_cookie_import_parse_json(payload.c_str());
  const bool rejected =
      batch != nullptr &&
      g_strcmp0(
          batch->detail_code,
          "manual_json_too_many_cookies") == 0;
  browser_cookie_import_batch_free(batch);
  return Expect(rejected, "manual JSON cookie limit drifted");
}

bool DiscoversVisibleProfileNamesAndRejectsDuplicates() {
  g_autofree gchar* config_root =
      g_dir_make_tmp("alera-browser-profile-test-XXXXXX", nullptr);
  if (!Expect(config_root != nullptr, "profile fixture was not created")) {
    return false;
  }
  g_setenv("XDG_CONFIG_HOME", config_root, TRUE);
  g_autofree gchar* browser_root =
      g_build_filename(config_root, "google-chrome", nullptr);
  for (const gchar* directory : {"Default", "Profile 1"}) {
    g_autofree gchar* network =
        g_build_filename(browser_root, directory, "Network", nullptr);
    g_mkdir_with_parents(network, 0700);
    g_autofree gchar* cookies =
        g_build_filename(network, "Cookies", nullptr);
    g_file_set_contents(cookies, "", 0, nullptr);
  }
  g_autofree gchar* local_state =
      g_build_filename(browser_root, "Local State", nullptr);
  const gchar* metadata =
      R"({"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Personal"}}}})";
  g_file_set_contents(local_state, metadata, -1, nullptr);

  g_autoptr(GPtrArray) profiles =
      browser_cookie_import_find_profiles("chrome");
  g_autofree gchar* detail = nullptr;
  const auto* selected = browser_cookie_import_select_profile(
      profiles, "Personal", &detail);
  const bool succeeded =
      Expect(
          profiles->len == 2,
          "Chromium source profiles were not discovered") &&
      Expect(
          g_strcmp0(
              static_cast<BrowserCookieImportProfile*>(
                  g_ptr_array_index(profiles, 0))
                  ->name,
              "Personal") == 0,
          "Chromium visible profile name was not resolved") &&
      Expect(
          selected == nullptr &&
              g_strcmp0(detail, "source_profile_ambiguous") == 0,
          "duplicate visible profile names were not rejected");
  std::error_code cleanup_error;
  std::filesystem::remove_all(config_root, cleanup_error);
  return succeeded;
}

}  // namespace

int main() {
  bool succeeded = true;
  succeeded &= SelectsOnlyAnExactUniqueProfile();
  succeeded &= RejectsOversizedManualJson();
  succeeded &= RejectsTooManyManualCookies();
  succeeded &= DiscoversVisibleProfileNamesAndRejectsDuplicates();
  return succeeded ? 0 : 1;
}
