#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_profile.h"
#include "browser_profile_storage.h"
#include "browser_value.h"

#include <filesystem>

namespace alera_browser {
namespace {

EncodableValue ProfileValue(const BrowserProfile& profile) {
  return EncodableValue(EncodableMap{
      {EncodableValue("id"), EncodableValue(profile.id())},
      {EncodableValue("storage"),
       EncodableValue(
           profile.ephemeral() ? "ephemeral" : "persistent")},
      {EncodableValue("isDefault"),
       EncodableValue(profile.id() == "default")}});
}

}  // namespace

bool HandleBrowserProfileMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result) {
  if (method == "profile.list") {
    flutter::EncodableList profiles;
    for (const auto& entry : plugin->profiles_) {
      profiles.push_back(ProfileValue(*entry.second));
    }
    Success(std::move(result), EncodableValue(std::move(profiles)));
    return true;
  }

  if (method == "profile.create") {
    const auto id = StringValue(arguments, "id");
    const auto storage =
        StringValue(arguments, "storage").value_or("persistent");
    if (!id.has_value() || !IsValidBrowserId(*id)) {
      Error(
          std::move(result), "invalid_profile",
          "Profile id must use 1-64 safe ASCII characters.");
      return true;
    }
    if (storage != "persistent" && storage != "ephemeral") {
      Error(
          std::move(result), "invalid_profile_storage",
          "Profile storage must be persistent or ephemeral.");
      return true;
    }
    const bool ephemeral = storage == "ephemeral";
    const auto existing = plugin->FindProfile(*id);
    if (existing) {
      if (existing->ephemeral() != ephemeral) {
        Error(
            std::move(result), "profile_storage_mismatch",
            "The existing profile uses different storage.");
      } else {
        Success(std::move(result), ProfileValue(*existing));
      }
      return true;
    }
    const auto root = ephemeral ? BrowserTemporaryRoot()
                                : BrowserProfileRoot();
    const auto suffix = ephemeral
                            ? *id + "-" +
                                  std::to_string(GetCurrentProcessId()) + "-" +
                                  std::to_string(GetTickCount64())
                            : *id;
    const auto data_path = root / Utf16(suffix);
    const auto storage_error =
        MaterializeBrowserProfileStorage(data_path, ephemeral);
    if (storage_error) {
      Error(
          std::move(result), "profile_create_failed",
          "The isolated browser profile storage could not be created.");
      return true;
    }
    auto profile = std::make_shared<BrowserProfile>(
        *id, ephemeral, data_path);
    plugin->profiles_[*id] = profile;
    Success(std::move(result), ProfileValue(*profile));
    return true;
  }

  if (method == "profile.delete") {
    const auto id = StringValue(arguments, "profileId");
    if (!id.has_value()) {
      Error(
          std::move(result), "invalid_profile",
          "A browser profile id is required.");
      return true;
    }
    if (*id == "default") {
      Error(
          std::move(result), "default_profile",
          "The default browser profile cannot be deleted.");
      return true;
    }
    const auto profile = plugin->FindProfile(*id);
    if (!profile) {
      Success(std::move(result));
      return true;
    }
    if (plugin->active_cookie_imports_.count(*id) != 0) {
      Error(
          std::move(result), "profile_in_use",
          "Wait for the browser cookie import to finish.");
      return true;
    }
    for (const auto& entry : plugin->pages_) {
      if (entry.second->profile_id() == *id) {
        Error(
            std::move(result), "profile_in_use",
            "Close every browser page using this profile first.");
        return true;
      }
    }
    if (!profile->DeleteStorage()) {
      plugin->profiles_[*id] = std::make_shared<BrowserProfile>(
          *id, false, BrowserProfileRoot() / Utf16(*id));
      Error(
          std::move(result), "profile_delete_failed",
          "The isolated browser profile storage could not be removed.");
      return true;
    }
    plugin->profiles_.erase(*id);
    Success(std::move(result));
    return true;
  }

  result->NotImplemented();
  return false;
}

}  // namespace alera_browser
