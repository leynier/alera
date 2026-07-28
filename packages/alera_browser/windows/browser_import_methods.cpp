#include "alera_browser_plugin.h"

#include "browser_cookie.h"
#include "browser_import_internal.h"
#include "browser_page.h"
#include "browser_platform_dispatcher.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <algorithm>
#include <memory>
#include <thread>

namespace alera_browser {
namespace {

EncodableValue ImportResult(
    const std::string& source,
    const std::string& profile_id,
    const std::string& outcome,
    int64_t imported,
    int64_t skipped,
    const std::string& detail_code = {}) {
  EncodableMap value{
      {EncodableValue("source"), EncodableValue(source)},
      {EncodableValue("profileId"), EncodableValue(profile_id)},
      {EncodableValue("outcome"), EncodableValue(outcome)},
      {EncodableValue("importedCount"), EncodableValue(imported)},
      {EncodableValue("skippedCount"), EncodableValue(skipped)}};
  if (!detail_code.empty()) {
    value[EncodableValue("detailCode")] =
        EncodableValue(detail_code);
  }
  return EncodableValue(std::move(value));
}

bool IsSupportedSource(const std::string& source) {
  if (source == "manualJson") {
    return true;
  }
  const auto& sources = WindowsBrowserImportSources();
  return std::find(sources.begin(), sources.end(), source) !=
         sources.end();
}

BrowserImportBatch LoadImport(
    const std::string& source,
    const std::optional<std::string>& source_profile_name,
    const std::optional<std::string>& json) {
  if (source == "manualJson") {
    if (!json.has_value()) {
      BrowserImportBatch batch;
      batch.outcome = "failed";
      batch.detail_code = "manual_json_required";
      return batch;
    }
    return ParseManualBrowserCookieJson(*json);
  }
  if (!source_profile_name.has_value() ||
      source_profile_name->empty()) {
    BrowserImportBatch batch;
    batch.outcome = "failed";
    batch.detail_code = "source_profile_required";
    return batch;
  }
  BrowserImportLocation location;
  const auto selection = SelectBrowserImportLocation(
      source, *source_profile_name, &location);
  if (selection != BrowserImportProfileSelection::found) {
    BrowserImportBatch batch;
    batch.outcome = "failed";
    batch.detail_code =
        selection == BrowserImportProfileSelection::ambiguous
            ? "source_profile_ambiguous"
            : "source_profile_not_found";
    return batch;
  }
  return source == "firefox"
             ? LoadFirefoxBrowserCookies(location)
             : LoadChromiumBrowserCookies(location);
}

flutter::EncodableList ProbeSources() {
  flutter::EncodableList statuses;
  for (const auto& source : WindowsBrowserImportSources()) {
    const auto locations = FindBrowserImportLocations(source);
    flutter::EncodableList profile_names;
    for (const auto& location : locations) {
      profile_names.emplace_back(location.profile_name);
    }
    const bool available = !locations.empty();
    EncodableMap status{
        {EncodableValue("source"), EncodableValue(source)},
        {EncodableValue("supported"), EncodableValue(true)},
        {EncodableValue("available"), EncodableValue(available)},
        {EncodableValue("profileNames"),
         EncodableValue(std::move(profile_names))}};
    if (!available) {
      status[EncodableValue("detailCode")] =
          EncodableValue("source_not_installed");
    }
    statuses.emplace_back(std::move(status));
  }
  statuses.emplace_back(EncodableMap{
      {EncodableValue("source"), EncodableValue("manualJson")},
      {EncodableValue("supported"), EncodableValue(true)},
      {EncodableValue("available"), EncodableValue(true)}});
  return statuses;
}

}  // namespace

bool HandleBrowserImportMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result) {
  if (method == "cookieImport.probe") {
    auto shared_result =
        std::shared_ptr<MethodResult>(std::move(result));
    const auto dispatcher = plugin->dispatcher();
    try {
      std::thread([dispatcher, shared_result]() {
        auto statuses = ProbeSources();
        dispatcher->Post(
            [shared_result, statuses = std::move(statuses)]() mutable {
              shared_result->Success(
                  EncodableValue(std::move(statuses)));
            });
      }).detach();
    } catch (const std::system_error&) {
      shared_result->Error(
          "import_probe_failed",
          "The cookie import worker could not start.");
    }
    return true;
  }
  if (method != "cookieImport.run") {
    result->NotImplemented();
    return false;
  }

  const auto profile_id = StringValue(arguments, "profileId");
  const auto source = StringValue(arguments, "source");
  if (!profile_id.has_value() ||
      !plugin->FindProfile(*profile_id)) {
    Error(
        std::move(result), "profile_not_found",
        "The browser profile does not exist.");
    return true;
  }
  if (!source.has_value() || !IsSupportedSource(*source)) {
    Success(
        std::move(result),
        ImportResult(
            source.value_or(""), *profile_id, "unsupported", 0, 0,
            "source_unsupported"));
    return true;
  }
  for (const auto& entry : plugin->pages_) {
    if (entry.second->profile_id() == *profile_id) {
      Success(
          std::move(result),
          ImportResult(
              *source, *profile_id, "failed", 0, 0,
              "profile_in_use"));
      return true;
    }
  }
  if (!plugin->active_cookie_imports_.insert(*profile_id).second) {
    Error(
        std::move(result), "import_in_progress",
        "This browser profile is already importing cookies.");
    return true;
  }

  auto shared_result =
      std::shared_ptr<MethodResult>(std::move(result));
  const auto dispatcher = plugin->dispatcher();
  const auto lifetime = plugin->lifetime();
  const auto target_profile_id = *profile_id;
  const auto target_source = *source;
  const auto source_profile_name =
      StringValue(arguments, "sourceProfileName");
  const auto json = StringValue(arguments, "json");
  try {
    std::thread(
        [plugin, dispatcher, lifetime, target_profile_id,
         target_source, source_profile_name, json, shared_result]() {
          auto batch = std::make_shared<BrowserImportBatch>(
              LoadImport(target_source, source_profile_name, json));
          dispatcher->Post(
              [plugin, lifetime, target_profile_id, target_source,
               batch, shared_result]() {
                if (lifetime.expired()) {
                  return;
                }
                if (!batch->succeeded()) {
                  plugin->active_cookie_imports_.erase(
                      target_profile_id);
                  shared_result->Success(ImportResult(
                      target_source, target_profile_id,
                      batch->outcome, 0, batch->skipped,
                      batch->detail_code));
                  return;
                }
                const auto profile =
                    plugin->FindProfile(target_profile_id);
                if (!profile) {
                  plugin->active_cookie_imports_.erase(
                      target_profile_id);
                  shared_result->Success(ImportResult(
                      target_source, target_profile_id, "failed", 0,
                      batch->skipped, "profile_not_found"));
                  return;
                }
                profile->EnsureCookieManager(
                    plugin->parent_window(),
                    [plugin, lifetime, target_profile_id,
                     target_source, batch, shared_result](
                        HRESULT ready,
                        ICoreWebView2CookieManager* manager) {
                      if (lifetime.expired()) {
                        return;
                      }
                      if (FAILED(ready) || manager == nullptr) {
                        plugin->active_cookie_imports_.erase(
                            target_profile_id);
                        shared_result->Success(ImportResult(
                            target_source, target_profile_id,
                            "failed", 0, batch->skipped,
                            "cookie_store_unavailable"));
                        return;
                      }
                      ImportBrowserCookiesAtomically(
                          manager, batch->cookies,
                          [plugin, lifetime, target_profile_id,
                           target_source, batch, shared_result](
                              HRESULT imported,
                              int64_t imported_count) {
                            if (lifetime.expired()) {
                              return;
                            }
                            plugin->active_cookie_imports_.erase(
                                target_profile_id);
                            if (FAILED(imported)) {
                              shared_result->Success(ImportResult(
                                  target_source,
                                  target_profile_id, "failed", 0,
                                  batch->skipped,
                                  "atomic_import_failed"));
                              return;
                            }
                            shared_result->Success(ImportResult(
                                target_source,
                                target_profile_id,
                                batch->skipped > 0
                                    ? "partiallyImported"
                                    : "imported",
                                imported_count, batch->skipped));
                          });
                    });
              });
        })
        .detach();
  } catch (const std::system_error&) {
    plugin->active_cookie_imports_.erase(target_profile_id);
    shared_result->Success(ImportResult(
        target_source, target_profile_id, "failed", 0, 0,
        "import_worker_unavailable"));
  }
  return true;
}

}  // namespace alera_browser
