#ifndef FLUTTER_PLUGIN_ALERA_BROWSER_PROFILE_STORAGE_H_
#define FLUTTER_PLUGIN_ALERA_BROWSER_PROFILE_STORAGE_H_

#include <filesystem>
#include <system_error>

namespace alera_browser {

inline std::error_code MaterializeBrowserProfileStorage(
    const std::filesystem::path& path,
    bool ephemeral) {
  std::error_code error;
  if (!ephemeral) {
    std::filesystem::create_directories(path, error);
  }
  return error;
}

}  // namespace alera_browser

#endif  // FLUTTER_PLUGIN_ALERA_BROWSER_PROFILE_STORAGE_H_
