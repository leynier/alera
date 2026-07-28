#ifndef ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_PROFILE_SELECTION_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_PROFILE_SELECTION_H_

#include <cstddef>
#include <string>
#include <vector>

namespace alera_browser {

enum class BrowserImportProfileSelection {
  found,
  not_found,
  ambiguous,
};

BrowserImportProfileSelection SelectBrowserImportProfileName(
    const std::vector<std::string>& profile_names,
    const std::string& selected_name,
    size_t* selected_index);
std::string ChromiumBrowserProfileDisplayName(
    const std::string& local_state_json,
    const std::string& profile_directory);
std::string FirefoxBrowserProfileDisplayName(
    const std::string& profile_directory);

}  // namespace alera_browser

#endif
