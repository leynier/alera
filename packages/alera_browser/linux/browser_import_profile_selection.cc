#include "browser_import_profile_selection.h"

LinuxBrowserImportProfileSelection select_linux_browser_import_profile(
    const std::vector<std::string>& profile_names,
    const std::string& selected_name,
    size_t* selected_index) {
  size_t matches = 0;
  size_t match_index = 0;
  for (size_t index = 0; index < profile_names.size(); ++index) {
    if (profile_names[index] == selected_name) {
      ++matches;
      match_index = index;
    }
  }
  if (matches == 0) {
    return LinuxBrowserImportProfileSelection::not_found;
  }
  if (matches > 1) {
    return LinuxBrowserImportProfileSelection::ambiguous;
  }
  if (selected_index != nullptr) {
    *selected_index = match_index;
  }
  return LinuxBrowserImportProfileSelection::found;
}
