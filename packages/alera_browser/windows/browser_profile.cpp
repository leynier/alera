#include "browser_profile.h"

#include "browser_value.h"

#include <WebView2EnvironmentOptions.h>
#include <wrl.h>

#include <system_error>
#include <utility>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

BrowserProfile::BrowserProfile(
    std::string id,
    bool ephemeral,
    std::filesystem::path data_path)
    : id_(std::move(id)),
      ephemeral_(ephemeral),
      data_path_(std::move(data_path)) {}

BrowserProfile::~BrowserProfile() {
  if (ephemeral_) {
    DeleteStorage();
  } else {
    Close();
  }
}

void BrowserProfile::EnsureEnvironment(ReadyCallback callback) {
  if (closed_) {
    callback(RO_E_CLOSED);
    return;
  }
  if (environment_) {
    callback(S_OK);
    return;
  }
  environment_waiters_.push_back(std::move(callback));
  if (environment_initializing_) {
    return;
  }
  environment_initializing_ = true;
  std::error_code path_error;
  std::filesystem::create_directories(data_path_, path_error);
  if (path_error) {
    FinishEnvironment(HRESULT_FROM_WIN32(path_error.value()), nullptr);
    return;
  }

  const auto self = shared_from_this();
  const HRESULT started = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, data_path_.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [self](
              HRESULT result,
              ICoreWebView2Environment* environment) -> HRESULT {
            self->FinishEnvironment(result, environment);
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    FinishEnvironment(started, nullptr);
  }
}

void BrowserProfile::FinishEnvironment(
    HRESULT result,
    ICoreWebView2Environment* value) {
  environment_initializing_ = false;
  if (SUCCEEDED(result) && value != nullptr && !closed_) {
    environment_ = value;
  } else if (SUCCEEDED(result)) {
    result = E_FAIL;
  }
  auto waiters = std::move(environment_waiters_);
  environment_waiters_.clear();
  for (auto& waiter : waiters) {
    waiter(result);
  }
}

HRESULT BrowserProfile::CreateController(
    HWND parent_window,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* handler) {
  if (!environment_) {
    return E_UNEXPECTED;
  }
  if (!ephemeral_) {
    return environment_->CreateCoreWebView2Controller(
        parent_window, handler);
  }
  ComPtr<ICoreWebView2Environment10> environment10;
  HRESULT result = environment_.As(&environment10);
  ComPtr<ICoreWebView2ControllerOptions> options;
  if (SUCCEEDED(result)) {
    result = environment10->CreateCoreWebView2ControllerOptions(&options);
  }
  if (SUCCEEDED(result)) {
    result = options->put_ProfileName(
        Utf16("alera-" + id_).c_str());
  }
  if (SUCCEEDED(result)) {
    result = options->put_IsInPrivateModeEnabled(TRUE);
  }
  return SUCCEEDED(result)
             ? environment10->CreateCoreWebView2ControllerWithOptions(
                   parent_window, options.Get(), handler)
             : result;
}

void BrowserProfile::EnsureCookieManager(
    HWND parent_window,
    CookieManagerCallback callback) {
  if (cookie_manager_) {
    callback(S_OK, cookie_manager_.Get());
    return;
  }
  cookie_waiters_.push_back(std::move(callback));
  if (cookie_manager_initializing_) {
    return;
  }
  cookie_manager_initializing_ = true;
  const auto self = shared_from_this();
  EnsureEnvironment([self, parent_window](HRESULT result) {
    if (FAILED(result) || !self->environment_) {
      self->FinishCookieManager(result, nullptr);
      return;
    }
    const HRESULT started = self->CreateController(
        parent_window,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [self](
                HRESULT created,
                ICoreWebView2Controller* controller) -> HRESULT {
              self->FinishCookieManager(created, controller);
              return S_OK;
            })
            .Get());
    if (FAILED(started)) {
      self->FinishCookieManager(started, nullptr);
    }
  });
}

void BrowserProfile::FinishCookieManager(
    HRESULT result,
    ICoreWebView2Controller* controller) {
  cookie_manager_initializing_ = false;
  if (SUCCEEDED(result) && controller != nullptr && !closed_) {
    cookie_controller_ = controller;
    cookie_controller_->put_IsVisible(FALSE);
    RECT bounds = {0, 0, 1, 1};
    cookie_controller_->put_Bounds(bounds);
    result = cookie_controller_->get_CoreWebView2(&cookie_webview_);
    if (SUCCEEDED(result) && cookie_webview_) {
      ComPtr<ICoreWebView2_2> webview2;
      result = cookie_webview_.As(&webview2);
      if (SUCCEEDED(result)) {
        result = webview2->get_CookieManager(&cookie_manager_);
      }
    }
  } else if (SUCCEEDED(result)) {
    result = E_FAIL;
  }
  auto waiters = std::move(cookie_waiters_);
  cookie_waiters_.clear();
  for (auto& waiter : waiters) {
    waiter(result, SUCCEEDED(result) ? cookie_manager_.Get() : nullptr);
  }
}

void BrowserProfile::Close() {
  if (closed_) {
    return;
  }
  closed_ = true;
  if (cookie_controller_) {
    cookie_controller_->Close();
  }
  cookie_manager_.Reset();
  cookie_webview_.Reset();
  cookie_controller_.Reset();
  environment_.Reset();
  for (auto& waiter : environment_waiters_) {
    waiter(RO_E_CLOSED);
  }
  environment_waiters_.clear();
  for (auto& waiter : cookie_waiters_) {
    waiter(RO_E_CLOSED, nullptr);
  }
  cookie_waiters_.clear();
}

bool BrowserProfile::DeleteStorage() {
  Close();
  std::error_code error;
  std::filesystem::remove_all(data_path_, error);
  return !error;
}

}  // namespace alera_browser
