#include "browser_import_profile_selection.h"

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

}  // namespace

int main() {
  const std::vector<std::string> names{
      "Default", "Profile 1", "Default"};
  size_t selected = 0;
  bool succeeded = true;
  succeeded &= Expect(
      select_linux_browser_import_profile(
          names, "Profile 1", &selected) ==
              LinuxBrowserImportProfileSelection::found &&
          selected == 1,
      "unique source profile was not selected");
  succeeded &= Expect(
      select_linux_browser_import_profile(
          names, "Missing", &selected) ==
          LinuxBrowserImportProfileSelection::not_found,
      "unknown source profile was accepted");
  succeeded &= Expect(
      select_linux_browser_import_profile(
          names, "Default", &selected) ==
          LinuxBrowserImportProfileSelection::ambiguous,
      "ambiguous source profile was accepted");
  return succeeded ? 0 : 1;
}
