#ifndef ALERA_BROWSER_WINDOWS_BROWSER_VALUE_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_VALUE_H_

#include "alera_browser_plugin.h"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace alera_browser {

const EncodableValue* FindValue(
    const EncodableMap& map,
    const std::string& key);
std::optional<std::string> StringValue(
    const EncodableMap& map,
    const std::string& key);
bool BoolValue(
    const EncodableMap& map,
    const std::string& key,
    bool fallback = false);
double DoubleValue(
    const EncodableMap& map,
    const std::string& key,
    double fallback = 0);
std::vector<std::string> StringListValue(
    const EncodableMap& map,
    const std::string& key);
EncodableMap MapValue(const EncodableMap& map, const std::string& key);

void Success(MethodResultPtr result);
void Success(MethodResultPtr result, EncodableValue value);
void Error(
    MethodResultPtr result,
    const std::string& code,
    const std::string& message);

EncodableMap BrowserEvent(
    const std::string& type,
    const std::string& page_id);
std::wstring Utf16(const std::string& value);
std::string Utf8(const wchar_t* value);
std::string Utf8(const std::wstring& value);
std::filesystem::path BrowserProfileRoot();
std::filesystem::path BrowserTemporaryRoot();
bool IsValidBrowserId(const std::string& value);
bool IsAllowedBrowserUrl(const std::string& value);
bool IsLoopbackUrl(const std::string& value);
bool IsAbsoluteFilePath(const std::string& value);
int64_t FileSize(const std::filesystem::path& path);
std::string FileName(const std::filesystem::path& path);
std::string HResultMessage(HRESULT result);

}  // namespace alera_browser

#endif
