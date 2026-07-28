#include "browser_value.h"

#include <ShlObj.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <system_error>

#ifndef ALERA_BROWSER_STORAGE_NAME
#define ALERA_BROWSER_STORAGE_NAME L"Alera"
#endif

namespace alera_browser {
namespace {

const EncodableValue kStringKey(const std::string& key) {
  return EncodableValue(key);
}

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char item) {
    return static_cast<char>(
        std::tolower(static_cast<unsigned char>(item)));
  });
  return value;
}

std::string UrlHost(const std::string& value) {
  const auto scheme = value.find("://");
  if (scheme == std::string::npos) {
    return {};
  }
  const auto start = scheme + 3;
  const auto end = value.find_first_of("/?#", start);
  auto authority = value.substr(start, end - start);
  const auto credentials = authority.rfind('@');
  if (credentials != std::string::npos) {
    authority.erase(0, credentials + 1);
  }
  if (!authority.empty() && authority.front() == '[') {
    const auto bracket = authority.find(']');
    return bracket == std::string::npos
               ? std::string()
               : authority.substr(1, bracket - 1);
  }
  const auto port = authority.rfind(':');
  return Lower(authority.substr(0, port));
}

std::filesystem::path KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR raw = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &raw)) ||
      raw == nullptr) {
    return {};
  }
  const std::filesystem::path path(raw);
  CoTaskMemFree(raw);
  return path;
}

}  // namespace

const EncodableValue* FindValue(
    const EncodableMap& map,
    const std::string& key) {
  const auto iterator = map.find(kStringKey(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::string> StringValue(
    const EncodableMap& map,
    const std::string& key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::nullopt
                         : std::optional<std::string>(*text);
}

bool BoolValue(
    const EncodableMap& map,
    const std::string& key,
    bool fallback) {
  const auto* value = FindValue(map, key);
  const auto* boolean =
      value == nullptr ? nullptr : std::get_if<bool>(value);
  return boolean == nullptr ? fallback : *boolean;
}

double DoubleValue(
    const EncodableMap& map,
    const std::string& key,
    double fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<double>(*number);
  }
  return fallback;
}

std::vector<std::string> StringListValue(
    const EncodableMap& map,
    const std::string& key) {
  const auto* value = FindValue(map, key);
  const auto* list =
      value == nullptr ? nullptr : std::get_if<flutter::EncodableList>(value);
  std::vector<std::string> result;
  if (list != nullptr) {
    for (const auto& item : *list) {
      if (const auto* text = std::get_if<std::string>(&item)) {
        result.push_back(*text);
      }
    }
  }
  return result;
}

EncodableMap MapValue(const EncodableMap& map, const std::string& key) {
  const auto* value = FindValue(map, key);
  const auto* nested =
      value == nullptr ? nullptr : std::get_if<EncodableMap>(value);
  return nested == nullptr ? EncodableMap() : *nested;
}

void Success(MethodResultPtr result) {
  result->Success();
}

void Success(MethodResultPtr result, EncodableValue value) {
  result->Success(value);
}

void Error(
    MethodResultPtr result,
    const std::string& code,
    const std::string& message) {
  result->Error(code, message);
}

EncodableMap BrowserEvent(
    const std::string& type,
    const std::string& page_id) {
  return {{EncodableValue("type"), EncodableValue(type)},
          {EncodableValue("pageId"), EncodableValue(page_id)}};
}

std::wstring Utf16(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int count = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (count <= 0) {
    return {};
  }
  std::wstring result(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), count);
  return result;
}

std::string Utf8(const wchar_t* value) {
  return value == nullptr ? std::string() : Utf8(std::wstring(value));
}

std::string Utf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int count = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (count <= 0) {
    return {};
  }
  std::string result(static_cast<size_t>(count), '\0');
  WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), count, nullptr, nullptr);
  return result;
}

std::filesystem::path BrowserProfileRoot() {
  return KnownFolder(FOLDERID_LocalAppData) / ALERA_BROWSER_STORAGE_NAME /
         L"Browser" /
         L"Profiles";
}

std::filesystem::path BrowserTemporaryRoot() {
  return KnownFolder(FOLDERID_LocalAppData) / ALERA_BROWSER_STORAGE_NAME /
         L"Browser" /
         L"Temporary";
}

bool IsValidBrowserId(const std::string& value) {
  if (value.empty() || value.size() > 64 ||
      value.find("..") != std::string::npos) {
    return false;
  }
  return std::all_of(value.begin(), value.end(), [](char item) {
    return std::isalnum(static_cast<unsigned char>(item)) != 0 ||
           item == '-' || item == '_' || item == '.';
  });
}

bool IsAllowedBrowserUrl(const std::string& value) {
  const auto lower = Lower(value);
  if (lower == "about:blank") {
    return true;
  }
  if (std::any_of(value.begin(), value.end(), [](unsigned char item) {
        return item <= 0x20 || item == 0x7f || item == '\\';
      })) {
    return false;
  }
  return (lower.rfind("https://", 0) == 0 ||
          lower.rfind("http://", 0) == 0) &&
         !UrlHost(value).empty() && value.find('@') == std::string::npos;
}

bool IsLoopbackUrl(const std::string& value) {
  const auto host = UrlHost(value);
  if (host == "localhost" || host == "::1" ||
      host.rfind("127.", 0) == 0) {
    return true;
  }
  return host.size() > 10 &&
         host.compare(host.size() - 10, 10, ".localhost") == 0;
}

bool IsAbsoluteFilePath(const std::string& value) {
  if (value.empty()) {
    return false;
  }
  return std::filesystem::path(Utf16(value)).is_absolute();
}

int64_t FileSize(const std::filesystem::path& path) {
  std::error_code error;
  const auto size = std::filesystem::file_size(path, error);
  return error ? 0 : static_cast<int64_t>(size);
}

std::string FileName(const std::filesystem::path& path) {
  return Utf8(path.filename().wstring());
}

std::string HResultMessage(HRESULT result) {
  wchar_t* buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, result, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  std::string message =
      length == 0 ? "Windows operation failed." : Utf8(buffer);
  LocalFree(buffer);
  while (!message.empty() &&
         (message.back() == '\r' || message.back() == '\n')) {
    message.pop_back();
  }
  return message;
}

}  // namespace alera_browser
