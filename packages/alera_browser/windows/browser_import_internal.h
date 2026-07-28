#ifndef ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_INTERNAL_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_INTERNAL_H_

#include "browser_cookie.h"
#include "browser_import_profile_selection.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace alera_browser {

struct BrowserImportLocation {
  std::string source;
  std::string profile_name;
  std::filesystem::path root;
  std::filesystem::path local_state;
  std::vector<std::filesystem::path> databases;
};

struct BrowserImportBatch {
  BrowserCookieList cookies;
  int64_t skipped = 0;
  std::string outcome;
  std::string detail_code;

  bool succeeded() const { return outcome.empty(); }
};

const std::vector<std::string>& WindowsBrowserImportSources();
std::vector<BrowserImportLocation> FindBrowserImportLocations(
    const std::string& source);
BrowserImportProfileSelection SelectBrowserImportLocation(
    const std::string& source,
    const std::string& profile_name,
    BrowserImportLocation* location);
BrowserImportBatch ParseManualBrowserCookieJson(
    const std::string& json);
BrowserImportBatch LoadChromiumBrowserCookies(
    const BrowserImportLocation& location);
BrowserImportBatch LoadFirefoxBrowserCookies(
    const BrowserImportLocation& location);
BrowserImportBatch DeduplicateBrowserImportBatch(
    BrowserImportBatch batch);

class BrowserDatabaseCopy {
 public:
  BrowserDatabaseCopy() = default;
  ~BrowserDatabaseCopy();
  BrowserDatabaseCopy(const BrowserDatabaseCopy&) = delete;
  BrowserDatabaseCopy& operator=(const BrowserDatabaseCopy&) = delete;

  static std::optional<BrowserDatabaseCopy> Create(
      const std::filesystem::path& source);

  BrowserDatabaseCopy(BrowserDatabaseCopy&& other) noexcept;
  BrowserDatabaseCopy& operator=(BrowserDatabaseCopy&& other) noexcept;

  const std::filesystem::path& path() const { return path_; }

 private:
  BrowserDatabaseCopy(
      std::filesystem::path directory,
      std::filesystem::path path);
  void Reset();

  std::filesystem::path directory_;
  std::filesystem::path path_;
};

std::optional<std::vector<uint8_t>> LoadChromiumEncryptionKey(
    const std::filesystem::path& local_state,
    std::string* detail_code);
std::optional<std::string> DecryptChromiumCookie(
    const std::vector<uint8_t>& encrypted,
    const std::vector<uint8_t>& key,
    bool has_domain_digest,
    const std::string& domain,
    std::string* detail_code);

}  // namespace alera_browser

#endif
