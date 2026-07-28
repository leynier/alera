#include "browser_page.h"

#include "alera_browser_plugin.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <wrl.h>

#include <algorithm>
#include <cmath>
#include <utility>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

void BrowserPage::Create(
    AleraBrowserPlugin* plugin,
    HWND parent_window,
    std::shared_ptr<BrowserProfile> profile,
    std::string id,
    std::optional<std::string> initial_url,
    std::optional<std::string> user_agent,
    std::optional<std::string> opener_page_id,
    bool transient,
    CreatedCallback callback) {
  auto page = std::shared_ptr<BrowserPage>(new BrowserPage(
      plugin, std::move(profile), std::move(id), std::move(initial_url),
      std::move(user_agent), std::move(opener_page_id), transient));
  page->profile_->EnsureEnvironment(
      [page, parent_window, callback = std::move(callback)](HRESULT result) {
        if (FAILED(result) || page->profile_->environment() == nullptr) {
          callback(result, nullptr);
          return;
        }
        const HRESULT started =
            page->profile_->CreateController(
                parent_window,
                Callback<
                    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [page, parent_window, callback](
                        HRESULT created,
                        ICoreWebView2Controller* controller) -> HRESULT {
                      page->FinishCreate(
                          parent_window, created, controller, callback);
                      return S_OK;
                    })
                    .Get());
        if (FAILED(started)) {
          callback(started, nullptr);
        }
      });
}

BrowserPage::BrowserPage(
    AleraBrowserPlugin* plugin,
    std::shared_ptr<BrowserProfile> profile,
    std::string id,
    std::optional<std::string> initial_url,
    std::optional<std::string> user_agent,
    std::optional<std::string> opener_page_id,
    bool transient)
    : plugin_(plugin),
      profile_(std::move(profile)),
      id_(std::move(id)),
      initial_url_(std::move(initial_url)),
      user_agent_(std::move(user_agent)),
      opener_page_id_(std::move(opener_page_id)),
      transient_(transient),
      adopted_(!transient) {}

BrowserPage::~BrowserPage() {
  Close();
}

void BrowserPage::FinishCreate(
    HWND parent_window,
    HRESULT result,
    ICoreWebView2Controller* controller,
    CreatedCallback callback) {
  if (FAILED(result) || controller == nullptr || closed_) {
    callback(FAILED(result) ? result : E_FAIL, nullptr);
    return;
  }
  controller_ = controller;
  result = controller_->get_CoreWebView2(&webview_);
  if (FAILED(result) || !webview_) {
    callback(FAILED(result) ? result : E_FAIL, nullptr);
    return;
  }
  ComPtr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(webview_->get_Settings(&settings)) && settings) {
    settings->put_IsScriptEnabled(TRUE);
    settings->put_AreDefaultScriptDialogsEnabled(FALSE);
    settings->put_AreDefaultContextMenusEnabled(FALSE);
    settings->put_IsStatusBarEnabled(FALSE);
    settings->put_AreDevToolsEnabled(FALSE);
  }
  if (user_agent_.has_value()) {
    ComPtr<ICoreWebView2Settings2> settings2;
    if (settings && SUCCEEDED(settings.As(&settings2))) {
      settings2->put_UserAgent(Utf16(*user_agent_).c_str());
    }
  }
  controller_->put_IsVisible(FALSE);
  controller_->put_Bounds({0, 0, 1, 1});
  RegisterEvents();
  if (initial_url_.has_value()) {
    webview_->Navigate(Utf16(*initial_url_).c_str());
  }
  callback(S_OK, shared_from_this());
}

const std::string& BrowserPage::profile_id() const {
  return profile_->id();
}

ICoreWebView2Environment* BrowserPage::environment() const {
  return profile_->environment();
}

void BrowserPage::SetAttached(bool attached) {
  attached_ = attached;
  UpdateVisibility();
}

void BrowserPage::SetObscured(bool obscured) {
  obscured_ = obscured;
  UpdateVisibility();
}

void BrowserPage::SetBounds(
    double x,
    double y,
    double width,
    double height,
    double scale) {
  x_ = x;
  y_ = y;
  width_ = width;
  height_ = height;
  scale_ = scale > 0 ? scale : 1;
  UpdateVisibility();
}

void BrowserPage::UpdateVisibility() {
  if (!controller_) {
    return;
  }
  const LONG left = static_cast<LONG>(std::lround(x_ * scale_));
  const LONG top = static_cast<LONG>(std::lround(y_ * scale_));
  const LONG width =
      std::max<LONG>(1, static_cast<LONG>(std::lround(width_ * scale_)));
  const LONG height =
      std::max<LONG>(1, static_cast<LONG>(std::lround(height_ * scale_)));
  controller_->put_Bounds({left, top, left + width, top + height});
  const bool visible =
      attached_ && !obscured_ && width_ > 0 && height_ > 0;
  controller_->put_IsVisible(visible ? TRUE : FALSE);
}

void BrowserPage::Navigate(
    const std::string& url,
    const std::map<std::string, std::string>& headers,
    std::function<void(HRESULT)> callback) {
  if (headers.empty()) {
    callback(webview_->Navigate(Utf16(url).c_str()));
    return;
  }
  ComPtr<ICoreWebView2Environment2> environment2;
  ComPtr<ICoreWebView2_2> webview2;
  HRESULT result = profile_->environment()->QueryInterface(
      IID_PPV_ARGS(&environment2));
  if (SUCCEEDED(result)) {
    result = webview_.As(&webview2);
  }
  std::wstring header_lines;
  for (const auto& [name, value] : headers) {
    header_lines += Utf16(name + ": " + value + "\r\n");
  }
  ComPtr<ICoreWebView2WebResourceRequest> request;
  if (SUCCEEDED(result)) {
    result = environment2->CreateWebResourceRequest(
        Utf16(url).c_str(), L"GET", nullptr, header_lines.c_str(), &request);
  }
  if (SUCCEEDED(result)) {
    result = webview2->NavigateWithWebResourceRequest(request.Get());
  }
  callback(result);
}

void BrowserPage::ExecuteScript(
    const std::string& script,
    ScriptCallback callback) {
  auto completion =
      std::make_shared<ScriptCallback>(std::move(callback));
  const HRESULT started = webview_->ExecuteScript(
      Utf16(script).c_str(),
      Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
          [completion](
              HRESULT result,
              LPCWSTR json) -> HRESULT {
            (*completion)(
                result, SUCCEEDED(result) ? Utf8(json) : std::string());
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    (*completion)(started, {});
  }
}

std::optional<std::string> BrowserPage::CurrentUrl() const {
  LPWSTR value = nullptr;
  if (FAILED(webview_->get_Source(&value)) || value == nullptr) {
    return std::nullopt;
  }
  const auto result = Utf8(value);
  CoTaskMemFree(value);
  return result;
}

std::optional<std::string> BrowserPage::Title() const {
  LPWSTR value = nullptr;
  if (FAILED(webview_->get_DocumentTitle(&value)) || value == nullptr) {
    return std::nullopt;
  }
  const auto result = Utf8(value);
  CoTaskMemFree(value);
  return result;
}

bool BrowserPage::CanGoBack() const {
  BOOL value = FALSE;
  return SUCCEEDED(webview_->get_CanGoBack(&value)) && value;
}

bool BrowserPage::CanGoForward() const {
  BOOL value = FALSE;
  return SUCCEEDED(webview_->get_CanGoForward(&value)) && value;
}

HRESULT BrowserPage::GoBack() {
  return webview_->GoBack();
}

HRESULT BrowserPage::GoForward() {
  return webview_->GoForward();
}

HRESULT BrowserPage::Reload() {
  return webview_->Reload();
}

HRESULT BrowserPage::Stop() {
  return webview_->Stop();
}

void BrowserPage::RegisterEvents() {
  RegisterBrowserPageEvents(shared_from_this());
}

void BrowserPage::UnregisterEvents() {
  UnregisterBrowserPageEvents(this);
}

void BrowserPage::Close() {
  if (closed_) {
    return;
  }
  closed_ = true;
  UnregisterEvents();
  if (controller_) {
    controller_->Close();
  }
  console_receiver_.Reset();
  webview_.Reset();
  controller_.Reset();
}

}  // namespace alera_browser
