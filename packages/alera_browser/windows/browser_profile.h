#ifndef ALERA_BROWSER_WINDOWS_BROWSER_PROFILE_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_PROFILE_H_

#include <WebView2.h>
#include <wrl/client.h>

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace alera_browser {

class BrowserProfile
    : public std::enable_shared_from_this<BrowserProfile> {
 public:
  using ReadyCallback = std::function<void(HRESULT)>;
  using CookieManagerCallback =
      std::function<void(HRESULT, ICoreWebView2CookieManager*)>;

  BrowserProfile(
      std::string id,
      bool ephemeral,
      std::filesystem::path data_path);
  ~BrowserProfile();
  BrowserProfile(const BrowserProfile&) = delete;
  BrowserProfile& operator=(const BrowserProfile&) = delete;

  const std::string& id() const { return id_; }
  bool ephemeral() const { return ephemeral_; }
  const std::filesystem::path& data_path() const { return data_path_; }
  ICoreWebView2Environment* environment() const {
    return environment_.Get();
  }

  void EnsureEnvironment(ReadyCallback callback);
  HRESULT CreateController(
      HWND parent_window,
      ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* handler);
  void EnsureCookieManager(HWND parent_window, CookieManagerCallback callback);
  void Close();
  bool DeleteStorage();

 private:
  void FinishEnvironment(HRESULT result, ICoreWebView2Environment* value);
  void FinishCookieManager(
      HRESULT result,
      ICoreWebView2Controller* controller);

  std::string id_;
  bool ephemeral_;
  std::filesystem::path data_path_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> cookie_controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> cookie_webview_;
  Microsoft::WRL::ComPtr<ICoreWebView2CookieManager> cookie_manager_;
  std::vector<ReadyCallback> environment_waiters_;
  std::vector<CookieManagerCallback> cookie_waiters_;
  bool environment_initializing_ = false;
  bool cookie_manager_initializing_ = false;
  bool closed_ = false;
};

}  // namespace alera_browser

#endif
