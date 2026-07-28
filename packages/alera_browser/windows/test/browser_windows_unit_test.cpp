#include "browser_decision_timeout.h"
#include "browser_import_limits.h"
#include "browser_import_profile_selection.h"
#include "browser_json.h"
#include "browser_profile_storage.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

bool Expect(bool value, const char* message) {
  if (!value) {
    std::cerr << message << '\n';
  }
  return value;
}

bool ParsesCookieExportShape() {
  alera_browser::BrowserJsonValue root;
  const std::string json =
      R"({"cookies":[{"name":"session","value":"ok",)"
      R"("domain":".example.com","secure":true,)"
      R"("expiresUtc":1780000000000}]})";
  if (!Expect(
          alera_browser::ParseBrowserJson(json, &root),
          "valid cookie JSON did not parse")) {
    return false;
  }
  const auto* cookies = root.Find("cookies");
  return Expect(
             cookies != nullptr &&
                 cookies->kind ==
                     alera_browser::BrowserJsonValue::Kind::array &&
                 cookies->array.size() == 1,
             "cookie array was not preserved") &&
         Expect(
             cookies->array.front().Find("secure")->Boolean() == true,
             "cookie boolean was not preserved") &&
         Expect(
             cookies->array.front().Find("expiresUtc")->Number() ==
                 1780000000000.0,
             "cookie expiration was not preserved");
}

bool ParsesEscapedUnicode() {
  alera_browser::BrowserJsonValue root;
  if (!Expect(
          alera_browser::ParseBrowserJson(
              R"({"value":"\uD83D\uDD12"})", &root),
          "valid surrogate pair did not parse")) {
    return false;
  }
  return Expect(
      root.Find("value")->String() == "\xF0\x9F\x94\x92",
      "surrogate pair was not encoded as UTF-8");
}

bool RejectsAmbiguousOrMalformedInput() {
  for (const auto* json : {
           R"({"name":"first","name":"second"})",
           R"({"cookies":[1,]})",
           R"({"value":"\uD800"})",
           R"([01])",
       }) {
    alera_browser::BrowserJsonValue root;
    if (!Expect(
            !alera_browser::ParseBrowserJson(json, &root),
            "malformed JSON was accepted")) {
      return false;
    }
  }
  return true;
}

bool SelectsOnlyAnExactUniqueProfile() {
  const std::vector<std::string> names{
      "Default", "Profile 1", "Default"};
  size_t selected = 0;
  return Expect(
             alera_browser::SelectBrowserImportProfileName(
                 names, "Profile 1", &selected) ==
                 alera_browser::BrowserImportProfileSelection::found &&
                 selected == 1,
             "unique source profile was not selected") &&
         Expect(
             alera_browser::SelectBrowserImportProfileName(
                 names, "Missing", &selected) ==
                 alera_browser::BrowserImportProfileSelection::not_found,
             "unknown source profile was accepted") &&
         Expect(
             alera_browser::SelectBrowserImportProfileName(
                 names, "Default", &selected) ==
                 alera_browser::BrowserImportProfileSelection::ambiguous,
             "ambiguous source profile was accepted");
}

bool ResolvesVisibleProfileNames() {
  const std::string local_state =
      R"({"profile":{"info_cache":{"Default":{"name":"Personal"}}}})";
  return Expect(
             alera_browser::ChromiumBrowserProfileDisplayName(
                 local_state, "Default") == "Personal",
             "Chromium profile display name was not resolved") &&
         Expect(
             alera_browser::ChromiumBrowserProfileDisplayName(
                 "invalid", "Profile 1") == "Profile 1",
             "Chromium profile directory fallback drifted") &&
         Expect(
             alera_browser::FirefoxBrowserProfileDisplayName(
                 "abc123.default-release") == "default-release",
             "Firefox profile display name was not resolved");
}

bool MaterializesOnlyPersistentProfileStorage() {
  const auto suffix = std::to_string(
      std::chrono::steady_clock::now().time_since_epoch().count());
  const auto root = std::filesystem::temp_directory_path() /
                    ("alera-browser-profile-test-" + suffix);
  const auto persistent = root / "persistent";
  const auto ephemeral = root / "ephemeral";
  std::error_code cleanup_error;
  std::filesystem::remove_all(root, cleanup_error);

  const auto persistent_error =
      alera_browser::MaterializeBrowserProfileStorage(persistent, false);
  const auto ephemeral_error =
      alera_browser::MaterializeBrowserProfileStorage(ephemeral, true);
  const bool succeeded =
      Expect(!persistent_error, "persistent profile storage failed") &&
      Expect(
          std::filesystem::is_directory(persistent),
          "persistent profile storage was not materialized") &&
      Expect(!ephemeral_error, "ephemeral profile preparation failed") &&
      Expect(
          !std::filesystem::exists(ephemeral),
          "ephemeral profile storage was persisted");
  std::filesystem::remove_all(root, cleanup_error);
  return succeeded;
}

}  // namespace

int main() {
  bool succeeded = true;
  succeeded &= Expect(
      alera_browser::kBrowserDecisionTimeoutMilliseconds == 30000,
      "security decision deadline drifted");
  succeeded &= Expect(
      alera_browser::kManualCookieJsonMaximumBytes ==
              16 * 1024 * 1024 &&
          alera_browser::kManualCookieMaximumCount == 100000,
      "manual cookie import limits drifted");
  succeeded &= Expect(
      !alera_browser::ManualCookieJsonWithinLimit(
          16 * 1024 * 1024 + 1),
      "oversized manual cookie JSON was accepted");
  succeeded &= ParsesCookieExportShape();
  succeeded &= ParsesEscapedUnicode();
  succeeded &= RejectsAmbiguousOrMalformedInput();
  succeeded &= SelectsOnlyAnExactUniqueProfile();
  succeeded &= ResolvesVisibleProfileNames();
  succeeded &= MaterializesOnlyPersistentProfileStorage();
  return succeeded ? 0 : 1;
}
