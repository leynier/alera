#include "browser_import_profile_selection.h"

#include "browser_json.h"

namespace alera_browser {

BrowserImportProfileSelection SelectBrowserImportProfileName(
    const std::vector<std::string>& profile_names,
    const std::string& selected_name,
    size_t* selected_index) {
  size_t match_count = 0;
  size_t match_index = 0;
  for (size_t index = 0; index < profile_names.size(); ++index) {
    if (profile_names[index] == selected_name) {
      ++match_count;
      match_index = index;
    }
  }
  if (match_count == 0) {
    return BrowserImportProfileSelection::not_found;
  }
  if (match_count > 1) {
    return BrowserImportProfileSelection::ambiguous;
  }
  if (selected_index != nullptr) {
    *selected_index = match_index;
  }
  return BrowserImportProfileSelection::found;
}

std::string ChromiumBrowserProfileDisplayName(
    const std::string& local_state_json,
    const std::string& profile_directory) {
  BrowserJsonValue root;
  if (!ParseBrowserJson(local_state_json, &root)) {
    return profile_directory;
  }
  const auto* profile = root.Find("profile");
  const auto* info_cache =
      profile == nullptr ? nullptr : profile->Find("info_cache");
  const auto* info =
      info_cache == nullptr ? nullptr : info_cache->Find(profile_directory);
  const auto* name = info == nullptr ? nullptr : info->Find("name");
  const auto display_name =
      name == nullptr ? std::nullopt : name->String();
  return display_name.has_value() && !display_name->empty()
             ? *display_name
             : profile_directory;
}

std::string FirefoxBrowserProfileDisplayName(
    const std::string& profile_directory) {
  const auto separator = profile_directory.find('.');
  return separator != std::string::npos &&
                 separator + 1 < profile_directory.size()
             ? profile_directory.substr(separator + 1)
             : profile_directory;
}

}  // namespace alera_browser
