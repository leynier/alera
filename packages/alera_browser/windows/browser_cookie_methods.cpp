#include "alera_browser_plugin.h"

#include "browser_cookie.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <memory>

namespace alera_browser {

bool HandleBrowserCookieMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result) {
  const auto profile_id = StringValue(arguments, "profileId");
  const auto profile =
      profile_id.has_value() ? plugin->FindProfile(*profile_id) : nullptr;
  if (!profile) {
    Error(
        std::move(result), "profile_not_found",
        "The browser profile does not exist.");
    return true;
  }
  auto shared_result =
      std::shared_ptr<MethodResult>(std::move(result));
  profile->EnsureCookieManager(
      plugin->parent_window(),
      [method, arguments, shared_result](
          HRESULT ready,
          ICoreWebView2CookieManager* manager) {
        if (FAILED(ready) || manager == nullptr) {
          shared_result->Error(
              "cookie_store_unavailable", HResultMessage(ready));
          return;
        }
        if (method == "cookies.get") {
          GetBrowserCookies(
              manager, StringValue(arguments, "url").value_or(""),
              [shared_result](
                  HRESULT value,
                  BrowserCookieList cookies) {
                if (FAILED(value)) {
                  shared_result->Error(
                      "cookie_read_failed", HResultMessage(value));
                  return;
                }
                flutter::EncodableList encoded;
                for (const auto& cookie : cookies) {
                  encoded.push_back(EncodeBrowserCookie(cookie));
                }
                shared_result->Success(
                    EncodableValue(std::move(encoded)));
              });
          return;
        }
        if (method == "cookies.set") {
          BrowserCookieData cookie;
          std::string error;
          const auto cookie_value = MapValue(arguments, "cookie");
          if (!DecodeBrowserCookie(cookie_value, &cookie, &error)) {
            shared_result->Error("invalid_cookie", error);
            return;
          }
          const HRESULT outcome = SetBrowserCookie(manager, cookie);
          if (FAILED(outcome)) {
            shared_result->Error(
                "cookie_write_failed", HResultMessage(outcome));
          } else {
            shared_result->Success();
          }
          return;
        }
        if (method == "cookies.delete") {
          GetBrowserCookies(
              manager, StringValue(arguments, "url").value_or(""),
              [manager, arguments, shared_result](
                  HRESULT value,
                  BrowserCookieList cookies) {
                if (FAILED(value)) {
                  shared_result->Error(
                      "cookie_delete_failed", HResultMessage(value));
                  return;
                }
                const auto name = StringValue(arguments, "name");
                const auto domain = StringValue(arguments, "domain");
                const auto path = StringValue(arguments, "path");
                int64_t removed = 0;
                HRESULT deleted = S_OK;
                for (const auto& cookie : cookies) {
                  if ((name.has_value() && cookie.name != *name) ||
                      (domain.has_value() &&
                       cookie.domain != *domain) ||
                      (path.has_value() && cookie.path != *path)) {
                    continue;
                  }
                  Microsoft::WRL::ComPtr<ICoreWebView2Cookie> native;
                  if (SUCCEEDED(manager->CreateCookie(
                          Utf16(cookie.name).c_str(),
                          Utf16(cookie.value).c_str(),
                          Utf16(cookie.domain).c_str(),
                          Utf16(cookie.path).c_str(), &native))) {
                    deleted = manager->DeleteCookie(native.Get());
                    if (FAILED(deleted)) {
                      break;
                    }
                    ++removed;
                  }
                }
                if (FAILED(deleted)) {
                  shared_result->Error(
                      "cookie_delete_failed",
                      HResultMessage(deleted));
                } else {
                  shared_result->Success(EncodableValue(removed));
                }
              });
          return;
        }
        shared_result->NotImplemented();
      });
  return true;
}

}  // namespace alera_browser
