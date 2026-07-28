#include "browser_import_internal.h"
#include "browser_value.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <fstream>
#include <iterator>
#include <map>
#include <system_error>

namespace alera_browser {
namespace {

constexpr uintmax_t kMaximumProfileMetadataBytes = 16 * 1024 * 1024;

std::string ReadProfileMetadata(
    const std::filesystem::path& path) {
  std::error_code error;
  const auto size = std::filesystem::file_size(path, error);
  if (error || size > kMaximumProfileMetadataBytes) {
    return {};
  }
  std::ifstream stream(path, std::ios::binary);
  return stream
             ? std::string(
                   std::istreambuf_iterator<char>(stream),
                   std::istreambuf_iterator<char>())
             : std::string();
}

std::optional<std::filesystem::path> EnvironmentPath(
    const wchar_t* name) {
  const DWORD length = GetEnvironmentVariableW(name, nullptr, 0);
  if (length == 0 || length > 32768) {
    return std::nullopt;
  }
  std::wstring value(length, L'\0');
  if (GetEnvironmentVariableW(name, value.data(), length) == 0) {
    return std::nullopt;
  }
  value.resize(length - 1);
  return std::filesystem::path(value);
}

std::vector<std::filesystem::path> ChromiumRoots(
    const std::string& source) {
  const auto local = EnvironmentPath(L"LOCALAPPDATA");
  if (!local.has_value()) {
    return {};
  }
  if (source == "chrome") {
    return {*local / L"Google" / L"Chrome" / L"User Data"};
  }
  if (source == "edge") {
    return {*local / L"Microsoft" / L"Edge" / L"User Data"};
  }
  if (source == "brave") {
    return {*local / L"BraveSoftware" / L"Brave-Browser" /
            L"User Data"};
  }
  if (source == "comet") {
    return {
        *local / L"Perplexity" / L"Comet" / L"User Data",
        *local / L"Comet" / L"User Data",
        *local / L"PerplexityAI" / L"Comet" / L"User Data"};
  }
  return {};
}

bool IsProfileDirectory(const std::filesystem::path& path) {
  const auto name = path.filename().wstring();
  return name == L"Default" || name.rfind(L"Profile ", 0) == 0 ||
         name.rfind(L"user-", 0) == 0;
}

std::vector<BrowserImportLocation> ChromiumLocations(
    const std::string& source,
    const std::filesystem::path& root) {
  std::vector<std::filesystem::path> profiles;
  std::error_code error;
  for (const auto& entry :
       std::filesystem::directory_iterator(root, error)) {
    if (!error && entry.is_directory(error) &&
        IsProfileDirectory(entry.path())) {
      profiles.push_back(entry.path());
    }
  }
  std::sort(profiles.begin(), profiles.end());
  const auto local_state = root / L"Local State";
  const auto metadata = ReadProfileMetadata(local_state);
  std::vector<BrowserImportLocation> values;
  for (const auto& profile : profiles) {
    const auto modern = profile / L"Network" / L"Cookies";
    const auto legacy = profile / L"Cookies";
    const auto directory = Utf8(profile.filename().wstring());
    const auto display_name =
        ChromiumBrowserProfileDisplayName(metadata, directory);
    if (std::filesystem::is_regular_file(modern, error)) {
      values.push_back(BrowserImportLocation{
          source, display_name, root, local_state, {modern}});
    } else if (std::filesystem::is_regular_file(legacy, error)) {
      values.push_back(BrowserImportLocation{
          source, display_name, root, local_state, {legacy}});
    }
  }
  return values;
}

std::vector<BrowserImportLocation> FirefoxLocations() {
  const auto roaming = EnvironmentPath(L"APPDATA");
  if (!roaming.has_value()) {
    return {};
  }
  const auto root = *roaming / L"Mozilla" / L"Firefox" / L"Profiles";
  std::vector<std::filesystem::path> databases;
  std::error_code error;
  for (const auto& entry :
       std::filesystem::directory_iterator(root, error)) {
    const auto candidate = entry.path() / L"cookies.sqlite";
    if (!error && entry.is_directory(error) &&
        std::filesystem::is_regular_file(candidate, error)) {
      databases.push_back(candidate);
    }
  }
  std::sort(
      databases.begin(), databases.end(),
      [](const auto& first, const auto& second) {
        const auto rank = [](const std::filesystem::path& value) {
          auto name = value.parent_path().filename().wstring();
          std::transform(
              name.begin(), name.end(), name.begin(),
              [](wchar_t character) {
                return static_cast<wchar_t>(std::towlower(character));
              });
          if (name.find(L"default-release") != std::wstring::npos) {
            return L"0-" + name;
          }
          if (name.find(L"default") != std::wstring::npos) {
            return L"1-" + name;
          }
          return L"2-" + name;
        };
        return rank(first) < rank(second);
      });
  std::vector<BrowserImportLocation> values;
  values.reserve(databases.size());
  for (const auto& database : databases) {
    const auto directory =
        Utf8(database.parent_path().filename().wstring());
    values.push_back(BrowserImportLocation{
        "firefox",
        FirefoxBrowserProfileDisplayName(directory),
        database.parent_path(), {}, {database}});
  }
  return values;
}

}  // namespace

const std::vector<std::string>& WindowsBrowserImportSources() {
  static const std::vector<std::string> sources{
      "chrome", "edge", "brave", "comet", "firefox"};
  return sources;
}

std::vector<BrowserImportLocation> FindBrowserImportLocations(
    const std::string& source) {
  if (source == "firefox") {
    return FirefoxLocations();
  }
  std::vector<BrowserImportLocation> values;
  for (const auto& root : ChromiumRoots(source)) {
    auto locations = ChromiumLocations(source, root);
    values.insert(
        values.end(),
        std::make_move_iterator(locations.begin()),
        std::make_move_iterator(locations.end()));
  }
  return values;
}

BrowserImportProfileSelection SelectBrowserImportLocation(
    const std::string& source,
    const std::string& profile_name,
    BrowserImportLocation* location) {
  const auto locations = FindBrowserImportLocations(source);
  std::vector<std::string> names;
  names.reserve(locations.size());
  for (const auto& candidate : locations) {
    names.push_back(candidate.profile_name);
  }
  size_t selected_index = 0;
  const auto selected = SelectBrowserImportProfileName(
      names, profile_name, &selected_index);
  if (selected == BrowserImportProfileSelection::found &&
      location != nullptr) {
    *location = locations[selected_index];
  }
  return selected;
}

BrowserImportBatch DeduplicateBrowserImportBatch(
    BrowserImportBatch batch) {
  std::map<std::string, BrowserCookieData> unique;
  for (auto& cookie : batch.cookies) {
    const auto key =
        cookie.domain + "\n" + cookie.path + "\n" + cookie.name;
    unique[key] = std::move(cookie);
  }
  batch.skipped +=
      static_cast<int64_t>(batch.cookies.size() - unique.size());
  batch.cookies.clear();
  batch.cookies.reserve(unique.size());
  for (auto& entry : unique) {
    batch.cookies.push_back(std::move(entry.second));
  }
  return batch;
}

}  // namespace alera_browser
