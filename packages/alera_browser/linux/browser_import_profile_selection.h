#ifndef ALERA_BROWSER_LINUX_BROWSER_IMPORT_PROFILE_SELECTION_H_
#define ALERA_BROWSER_LINUX_BROWSER_IMPORT_PROFILE_SELECTION_H_

#include <cstddef>
#include <string>
#include <vector>

enum class LinuxBrowserImportProfileSelection {
  found,
  not_found,
  ambiguous,
};

LinuxBrowserImportProfileSelection select_linux_browser_import_profile(
    const std::vector<std::string>& profile_names,
    const std::string& selected_name,
    size_t* selected_index);

#endif
