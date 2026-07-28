#include "browser_import_internal.h"

#include <windows.h>

#include <system_error>

namespace alera_browser {
namespace {

std::optional<std::filesystem::path> TemporaryDirectory() {
  std::wstring root(MAX_PATH + 1, L'\0');
  const DWORD length =
      GetTempPathW(static_cast<DWORD>(root.size()), root.data());
  if (length == 0 || length >= root.size()) {
    return std::nullopt;
  }
  root.resize(length);
  for (int attempt = 0; attempt < 16; ++attempt) {
    const auto name =
        L"alera-browser-import-" +
        std::to_wstring(GetCurrentProcessId()) + L"-" +
        std::to_wstring(GetTickCount64()) + L"-" +
        std::to_wstring(attempt);
    const auto path = std::filesystem::path(root) / name;
    std::error_code error;
    if (std::filesystem::create_directory(path, error)) {
      return path;
    }
  }
  return std::nullopt;
}

}  // namespace

BrowserDatabaseCopy::BrowserDatabaseCopy(
    std::filesystem::path directory,
    std::filesystem::path path)
    : directory_(std::move(directory)), path_(std::move(path)) {}

BrowserDatabaseCopy::~BrowserDatabaseCopy() {
  Reset();
}

BrowserDatabaseCopy::BrowserDatabaseCopy(
    BrowserDatabaseCopy&& other) noexcept
    : directory_(std::move(other.directory_)),
      path_(std::move(other.path_)) {
  other.directory_.clear();
  other.path_.clear();
}

BrowserDatabaseCopy& BrowserDatabaseCopy::operator=(
    BrowserDatabaseCopy&& other) noexcept {
  if (this != &other) {
    Reset();
    directory_ = std::move(other.directory_);
    path_ = std::move(other.path_);
    other.directory_.clear();
    other.path_.clear();
  }
  return *this;
}

std::optional<BrowserDatabaseCopy> BrowserDatabaseCopy::Create(
    const std::filesystem::path& source) {
  const auto directory = TemporaryDirectory();
  if (!directory.has_value()) {
    return std::nullopt;
  }
  const auto destination = *directory / source.filename();
  std::error_code error;
  std::filesystem::copy_file(
      source, destination,
      std::filesystem::copy_options::overwrite_existing, error);
  if (error) {
    std::filesystem::remove_all(*directory, error);
    return std::nullopt;
  }
  for (const wchar_t* suffix : {L"-wal", L"-shm"}) {
    const auto sidecar = std::filesystem::path(source.wstring() + suffix);
    if (!std::filesystem::is_regular_file(sidecar, error)) {
      error.clear();
      continue;
    }
    const auto target =
        std::filesystem::path(destination.wstring() + suffix);
    std::filesystem::copy_file(
        sidecar, target,
        std::filesystem::copy_options::overwrite_existing, error);
    if (error) {
      std::filesystem::remove_all(*directory, error);
      return std::nullopt;
    }
  }
  return BrowserDatabaseCopy(*directory, destination);
}

void BrowserDatabaseCopy::Reset() {
  if (directory_.empty()) {
    return;
  }
  std::error_code error;
  std::filesystem::remove_all(directory_, error);
  directory_.clear();
  path_.clear();
}

}  // namespace alera_browser
