#ifndef ALERA_BROWSER_WINDOWS_BROWSER_COOKIE_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_COOKIE_H_

#include "alera_browser_plugin.h"

#include <WebView2.h>
#include <wrl/client.h>

#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace alera_browser {

struct BrowserCookieData {
  std::string name;
  std::string value;
  std::string domain;
  std::string path = "/";
  std::optional<double> expires_unix_seconds;
  bool secure = false;
  bool http_only = false;
  std::optional<COREWEBVIEW2_COOKIE_SAME_SITE_KIND> same_site;
  std::optional<bool> session;
};

using BrowserCookieList = std::vector<BrowserCookieData>;
using BrowserCookieListCallback =
    std::function<void(HRESULT, BrowserCookieList)>;
using BrowserCookieImportCallback =
    std::function<void(HRESULT, int64_t)>;

bool DecodeBrowserCookie(
    const EncodableMap& value,
    BrowserCookieData* cookie,
    std::string* error);
EncodableValue EncodeBrowserCookie(const BrowserCookieData& cookie);
void GetBrowserCookies(
    ICoreWebView2CookieManager* manager,
    const std::string& url,
    BrowserCookieListCallback callback);
HRESULT SetBrowserCookie(
    ICoreWebView2CookieManager* manager,
    const BrowserCookieData& cookie);
void ImportBrowserCookiesAtomically(
    ICoreWebView2CookieManager* manager,
    const BrowserCookieList& cookies,
    BrowserCookieImportCallback callback);

}  // namespace alera_browser

#endif
