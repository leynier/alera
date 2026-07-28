#include "browser_cookie.h"

#include "browser_value.h"

#include <wrl.h>

#include <cmath>
#include <map>
#include <memory>
#include <utility>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

std::optional<BrowserCookieData> ReadNativeCookie(
    ICoreWebView2Cookie* value) {
  LPWSTR raw_name = nullptr;
  LPWSTR raw_value = nullptr;
  LPWSTR raw_domain = nullptr;
  LPWSTR raw_path = nullptr;
  if (FAILED(value->get_Name(&raw_name)) ||
      FAILED(value->get_Value(&raw_value)) ||
      FAILED(value->get_Domain(&raw_domain)) ||
      FAILED(value->get_Path(&raw_path))) {
    CoTaskMemFree(raw_name);
    CoTaskMemFree(raw_value);
    CoTaskMemFree(raw_domain);
    CoTaskMemFree(raw_path);
    return std::nullopt;
  }
  BrowserCookieData cookie;
  cookie.name = Utf8(raw_name);
  cookie.value = Utf8(raw_value);
  cookie.domain = Utf8(raw_domain);
  cookie.path = Utf8(raw_path);
  CoTaskMemFree(raw_name);
  CoTaskMemFree(raw_value);
  CoTaskMemFree(raw_domain);
  CoTaskMemFree(raw_path);
  BOOL boolean = FALSE;
  if (SUCCEEDED(value->get_IsSecure(&boolean))) {
    cookie.secure = boolean == TRUE;
  }
  if (SUCCEEDED(value->get_IsHttpOnly(&boolean))) {
    cookie.http_only = boolean == TRUE;
  }
  if (SUCCEEDED(value->get_IsSession(&boolean))) {
    cookie.session = boolean == TRUE;
  }
  double expires = 0;
  if (cookie.session != true &&
      SUCCEEDED(value->get_Expires(&expires)) && expires > 0) {
    cookie.expires_unix_seconds = expires;
  }
  COREWEBVIEW2_COOKIE_SAME_SITE_KIND same_site;
  if (SUCCEEDED(value->get_SameSite(&same_site))) {
    cookie.same_site = same_site;
  }
  return cookie;
}

HRESULT CreateNativeCookie(
    ICoreWebView2CookieManager* manager,
    const BrowserCookieData& cookie,
    ComPtr<ICoreWebView2Cookie>* result) {
  HRESULT value = manager->CreateCookie(
      Utf16(cookie.name).c_str(), Utf16(cookie.value).c_str(),
      Utf16(cookie.domain).c_str(), Utf16(cookie.path).c_str(),
      result->ReleaseAndGetAddressOf());
  if (SUCCEEDED(value) && cookie.expires_unix_seconds.has_value()) {
    value = (*result)->put_Expires(*cookie.expires_unix_seconds);
  }
  if (SUCCEEDED(value)) {
    value = (*result)->put_IsSecure(cookie.secure ? TRUE : FALSE);
  }
  if (SUCCEEDED(value)) {
    value = (*result)->put_IsHttpOnly(cookie.http_only ? TRUE : FALSE);
  }
  if (SUCCEEDED(value) && cookie.same_site.has_value()) {
    value = (*result)->put_SameSite(*cookie.same_site);
  }
  return value;
}

std::optional<std::string> SameSiteName(
    COREWEBVIEW2_COOKIE_SAME_SITE_KIND value) {
  switch (value) {
    case COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE:
      return "none";
    case COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX:
      return "lax";
    case COREWEBVIEW2_COOKIE_SAME_SITE_KIND_STRICT:
      return "strict";
    default:
      return std::nullopt;
  }
}

std::string CookieKey(const BrowserCookieData& cookie) {
  return cookie.domain + "\n" + cookie.path + "\n" + cookie.name;
}

bool CookiesEquivalent(
    const BrowserCookieData& first,
    const BrowserCookieData& second) {
  const bool expiration_matches =
      first.expires_unix_seconds.has_value() ==
          second.expires_unix_seconds.has_value() &&
      (!first.expires_unix_seconds.has_value() ||
       std::abs(
           *first.expires_unix_seconds -
           *second.expires_unix_seconds) < 1.0);
  return first.name == second.name && first.value == second.value &&
         first.domain == second.domain && first.path == second.path &&
         first.secure == second.secure &&
         first.http_only == second.http_only &&
         first.same_site == second.same_site &&
         first.session == second.session && expiration_matches;
}

std::map<std::string, BrowserCookieData> CookieIndex(
    const BrowserCookieList& cookies) {
  std::map<std::string, BrowserCookieData> index;
  for (const auto& cookie : cookies) {
    index[CookieKey(cookie)] = cookie;
  }
  return index;
}

bool ContainsCookies(
    const BrowserCookieList& actual,
    const BrowserCookieList& expected) {
  const auto indexed = CookieIndex(actual);
  for (const auto& cookie : expected) {
    const auto iterator = indexed.find(CookieKey(cookie));
    if (iterator == indexed.end() ||
        !CookiesEquivalent(iterator->second, cookie)) {
      return false;
    }
  }
  return true;
}

void RestoreBrowserCookies(
    ICoreWebView2CookieManager* manager,
    BrowserCookieList baseline,
    HRESULT original_failure,
    BrowserCookieImportCallback callback) {
  HRESULT restored = manager->DeleteAllCookies();
  for (const auto& cookie : baseline) {
    if (SUCCEEDED(restored)) {
      restored = SetBrowserCookie(manager, cookie);
    }
  }
  if (FAILED(restored)) {
    callback(E_UNEXPECTED, 0);
    return;
  }
  GetBrowserCookies(
      manager, "",
      [baseline = std::move(baseline), original_failure,
       callback = std::move(callback)](
          HRESULT read,
          BrowserCookieList current) {
        const bool exact =
            SUCCEEDED(read) && current.size() == baseline.size() &&
            ContainsCookies(current, baseline);
        callback(exact ? original_failure : E_UNEXPECTED, 0);
      });
}

}  // namespace

bool DecodeBrowserCookie(
    const EncodableMap& value,
    BrowserCookieData* cookie,
    std::string* error) {
  const auto name = StringValue(value, "name");
  const auto body = StringValue(value, "value");
  const auto domain = StringValue(value, "domain");
  if (!name.has_value() || name->empty() || !body.has_value() ||
      !domain.has_value() || domain->empty()) {
    *error = "Cookie name, value, and domain are required.";
    return false;
  }
  cookie->name = *name;
  cookie->value = *body;
  cookie->domain = *domain;
  cookie->path = StringValue(value, "path").value_or("/");
  cookie->secure = BoolValue(value, "secure");
  cookie->http_only = BoolValue(value, "httpOnly");
  if (const auto* raw_expires = FindValue(value, "expiresUtc")) {
    if (const auto* milliseconds = std::get_if<int64_t>(raw_expires)) {
      cookie->expires_unix_seconds =
          static_cast<double>(*milliseconds) / 1000.0;
    } else if (
        const auto* milliseconds32 =
            std::get_if<int32_t>(raw_expires)) {
      cookie->expires_unix_seconds =
          static_cast<double>(*milliseconds32) / 1000.0;
    }
  }
  const auto same_site = StringValue(value, "sameSite");
  if (same_site == "none") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE;
  } else if (same_site == "lax") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX;
  } else if (same_site == "strict") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_STRICT;
  }
  if (const auto* raw_session = FindValue(value, "session")) {
    if (const auto* session = std::get_if<bool>(raw_session)) {
      cookie->session = *session;
    }
  }
  return true;
}

EncodableValue EncodeBrowserCookie(const BrowserCookieData& cookie) {
  EncodableMap value{
      {EncodableValue("name"), EncodableValue(cookie.name)},
      {EncodableValue("value"), EncodableValue(cookie.value)},
      {EncodableValue("domain"), EncodableValue(cookie.domain)},
      {EncodableValue("path"), EncodableValue(cookie.path)},
      {EncodableValue("secure"), EncodableValue(cookie.secure)},
      {EncodableValue("httpOnly"), EncodableValue(cookie.http_only)},
  };
  if (cookie.expires_unix_seconds.has_value()) {
    value[EncodableValue("expiresUtc")] = EncodableValue(
        static_cast<int64_t>(*cookie.expires_unix_seconds * 1000));
  }
  if (cookie.same_site.has_value()) {
    const auto name = SameSiteName(*cookie.same_site);
    if (name.has_value()) {
      value[EncodableValue("sameSite")] = EncodableValue(*name);
    }
  }
  if (cookie.session.has_value()) {
    value[EncodableValue("session")] = EncodableValue(*cookie.session);
  }
  return EncodableValue(std::move(value));
}

void GetBrowserCookies(
    ICoreWebView2CookieManager* manager,
    const std::string& url,
    BrowserCookieListCallback callback) {
  auto completion =
      std::make_shared<BrowserCookieListCallback>(std::move(callback));
  const HRESULT started = manager->GetCookies(
      url.empty() ? nullptr : Utf16(url).c_str(),
      Callback<ICoreWebView2GetCookiesCompletedHandler>(
          [completion](
              HRESULT result,
              ICoreWebView2CookieList* values) -> HRESULT {
            BrowserCookieList cookies;
            UINT count = 0;
            if (SUCCEEDED(result) && values != nullptr) {
              result = values->get_Count(&count);
            }
            for (UINT index = 0; SUCCEEDED(result) && index < count;
                 ++index) {
              ComPtr<ICoreWebView2Cookie> value;
              result = values->GetValueAtIndex(index, &value);
              if (SUCCEEDED(result)) {
                const auto cookie = ReadNativeCookie(value.Get());
                if (cookie.has_value()) {
                  cookies.push_back(*cookie);
                }
              }
            }
            (*completion)(result, std::move(cookies));
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    (*completion)(started, {});
  }
}

HRESULT SetBrowserCookie(
    ICoreWebView2CookieManager* manager,
    const BrowserCookieData& cookie) {
  ComPtr<ICoreWebView2Cookie> native;
  HRESULT result = CreateNativeCookie(manager, cookie, &native);
  if (SUCCEEDED(result)) {
    result = manager->AddOrUpdateCookie(native.Get());
  }
  return result;
}

void ImportBrowserCookiesAtomically(
    ICoreWebView2CookieManager* manager,
    const BrowserCookieList& cookies,
    BrowserCookieImportCallback callback) {
  GetBrowserCookies(
      manager, "",
      [manager, cookies, callback = std::move(callback)](
          HRESULT result,
          BrowserCookieList original) {
        if (FAILED(result)) {
          callback(result, 0);
          return;
        }
        int64_t imported = 0;
        for (const auto& cookie : cookies) {
          result = SetBrowserCookie(manager, cookie);
          if (FAILED(result)) {
            RestoreBrowserCookies(
                manager, std::move(original), result,
                std::move(callback));
            return;
          }
          ++imported;
        }
        GetBrowserCookies(
            manager, "",
            [manager, cookies, original = std::move(original), imported,
             callback = std::move(callback)](
                HRESULT verified,
                BrowserCookieList current) mutable {
              if (SUCCEEDED(verified) &&
                  ContainsCookies(current, cookies)) {
                callback(S_OK, imported);
                return;
              }
              RestoreBrowserCookies(
                  manager, std::move(original),
                  FAILED(verified) ? verified : E_FAIL,
                  std::move(callback));
            });
      });
}

}  // namespace alera_browser
