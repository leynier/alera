#include "browser_page.h"

#include "alera_browser_plugin.h"
#include "browser_json.h"
#include "browser_value.h"

#include <wrl.h>

#include <memory>
#include <string>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

void EmitUrlEvent(
    const std::shared_ptr<BrowserPage>& page,
    const std::string& type,
    const std::string& url) {
  auto event = BrowserEvent(type, page->id());
  event[EncodableValue("url")] = EncodableValue(url);
  page->plugin()->Emit(std::move(event));
}

std::string NavigationError(COREWEBVIEW2_WEB_ERROR_STATUS status) {
  return "WebView2 navigation failed with status " +
         std::to_string(static_cast<int>(status)) + ".";
}

std::optional<EncodableMap> ConsoleEvent(
    const BrowserPage& page,
    const std::string& json) {
  BrowserJsonValue root;
  if (!ParseBrowserJson(json, &root)) {
    return std::nullopt;
  }
  const auto* entry = root.Find("entry");
  const auto text =
      entry == nullptr || entry->Find("text") == nullptr
          ? std::nullopt
          : entry->Find("text")->String();
  if (!text.has_value()) {
    return std::nullopt;
  }
  auto level =
      entry->Find("level") == nullptr
          ? std::string("unknown")
          : entry->Find("level")->String().value_or("unknown");
  if (level == "verbose") {
    level = "debug";
  }
  auto message = *text;
  constexpr size_t kMaximumConsoleMessageBytes = 16 * 1024;
  if (message.size() > kMaximumConsoleMessageBytes) {
    message.resize(kMaximumConsoleMessageBytes);
  }
  auto event = BrowserEvent("console", page.id());
  event[EncodableValue("level")] = EncodableValue(level);
  event[EncodableValue("message")] =
      EncodableValue(std::move(message));
  return event;
}

}  // namespace

void RegisterBrowserPageEvents(const std::shared_ptr<BrowserPage>& page) {
  auto weak = std::weak_ptr<BrowserPage>(page);
  auto* webview = page->webview();
  auto& tokens = page->event_tokens();

  webview->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [weak](
              ICoreWebView2*,
              ICoreWebView2NavigationStartingEventArgs* arguments) -> HRESULT {
            const auto page = weak.lock();
            if (!page) {
              return S_OK;
            }
            LPWSTR raw_url = nullptr;
            if (SUCCEEDED(arguments->get_Uri(&raw_url)) &&
                raw_url != nullptr) {
              const auto url = Utf8(raw_url);
              CoTaskMemFree(raw_url);
              if (!IsAllowedBrowserUrl(url)) {
                arguments->put_Cancel(TRUE);
                auto event = BrowserEvent("loadFailed", page->id());
                event[EncodableValue("url")] = EncodableValue(url);
                event[EncodableValue("description")] =
                    EncodableValue("Blocked browser URL scheme.");
                page->plugin()->Emit(std::move(event));
                return S_OK;
              }
              EmitUrlEvent(page, "navigationStarted", url);
            }
            auto progress = BrowserEvent("progress", page->id());
            progress[EncodableValue("progress")] = EncodableValue(0.0);
            page->plugin()->Emit(std::move(progress));
            return S_OK;
          })
          .Get(),
      &tokens.navigation_starting);

  webview->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [weak](
              ICoreWebView2*,
              ICoreWebView2ContentLoadingEventArgs* arguments) -> HRESULT {
            const auto page = weak.lock();
            if (!page) {
              return S_OK;
            }
            BOOL is_error_page = FALSE;
            if (SUCCEEDED(arguments->get_IsErrorPage(&is_error_page)) &&
                is_error_page) {
              return S_OK;
            }
            const auto url = page->CurrentUrl();
            if (url.has_value()) {
              EmitUrlEvent(page, "navigationCommitted", *url);
            }
            return S_OK;
          })
          .Get(),
      &tokens.content_loading);

  webview->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [weak](ICoreWebView2*, ICoreWebView2SourceChangedEventArgs*) {
            const auto page = weak.lock();
            const auto url = page ? page->CurrentUrl() : std::nullopt;
            if (page && url.has_value()) {
              EmitUrlEvent(page, "urlChanged", *url);
            }
            return S_OK;
          })
          .Get(),
      &tokens.source_changed);

  webview->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [weak](
              ICoreWebView2*,
              ICoreWebView2NavigationCompletedEventArgs* arguments) {
            const auto page = weak.lock();
            if (!page) {
              return S_OK;
            }
            BOOL succeeded = FALSE;
            arguments->get_IsSuccess(&succeeded);
            const auto url = page->CurrentUrl().value_or("about:blank");
            if (succeeded) {
              auto event = BrowserEvent("navigationFinished", page->id());
              event[EncodableValue("url")] = EncodableValue(url);
              event[EncodableValue("title")] =
                  EncodableValue(page->Title().value_or(""));
              event[EncodableValue("canGoBack")] =
                  EncodableValue(page->CanGoBack());
              event[EncodableValue("canGoForward")] =
                  EncodableValue(page->CanGoForward());
              page->plugin()->Emit(std::move(event));
            } else {
              COREWEBVIEW2_WEB_ERROR_STATUS status =
                  COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
              arguments->get_WebErrorStatus(&status);
              auto event = BrowserEvent("loadFailed", page->id());
              event[EncodableValue("url")] = EncodableValue(url);
              event[EncodableValue("description")] =
                  EncodableValue(NavigationError(status));
              page->plugin()->Emit(std::move(event));
            }
            auto progress = BrowserEvent("progress", page->id());
            progress[EncodableValue("progress")] = EncodableValue(1.0);
            page->plugin()->Emit(std::move(progress));
            return S_OK;
          })
          .Get(),
      &tokens.navigation_completed);

  webview->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [weak](ICoreWebView2*, IUnknown*) {
            const auto page = weak.lock();
            const auto url = page ? page->CurrentUrl() : std::nullopt;
            if (page && url.has_value()) {
              EmitUrlEvent(page, "urlChanged", *url);
            }
            return S_OK;
          })
          .Get(),
      &tokens.title_changed);

  webview->add_WindowCloseRequested(
      Callback<ICoreWebView2WindowCloseRequestedEventHandler>(
          [weak](ICoreWebView2*, IUnknown*) {
            const auto page = weak.lock();
            if (!page) {
              return S_OK;
            }
            auto* plugin = page->plugin();
            const auto page_id = page->id();
            plugin->RemovePage(page_id);
            plugin->Emit(BrowserEvent("pageClosed", page_id));
            return S_OK;
          })
          .Get(),
      &tokens.window_close_requested);

  webview->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [weak](
              ICoreWebView2*,
              ICoreWebView2PermissionRequestedEventArgs* arguments) {
            const auto page = weak.lock();
            if (page) {
              page->plugin()->StartPermissionDecision(page, arguments);
            } else {
              arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
            }
            return S_OK;
          })
          .Get(),
      &tokens.permission_requested);

  webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [weak](
              ICoreWebView2*,
              ICoreWebView2NewWindowRequestedEventArgs* arguments) {
            const auto page = weak.lock();
            if (page) {
              page->plugin()->StartPopupDecision(page, arguments);
            } else {
              arguments->put_Handled(TRUE);
            }
            return S_OK;
          })
          .Get(),
      &tokens.new_window_requested);

  ComPtr<ICoreWebView2_4> webview4;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview4)))) {
    webview4->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [weak](
                ICoreWebView2*,
                ICoreWebView2DownloadStartingEventArgs* arguments) {
              const auto page = weak.lock();
              if (page) {
                page->plugin()->StartDownloadDecision(page, arguments);
              } else {
                arguments->put_Cancel(TRUE);
              }
              return S_OK;
            })
            .Get(),
        &tokens.download_starting);
  }

  ComPtr<ICoreWebView2_14> webview14;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview14)))) {
    webview14->add_ServerCertificateErrorDetected(
        Callback<ICoreWebView2ServerCertificateErrorDetectedEventHandler>(
            [weak](
                ICoreWebView2*,
                ICoreWebView2ServerCertificateErrorDetectedEventArgs*
                    arguments) {
              const auto page = weak.lock();
              if (page) {
                page->plugin()->StartTlsDecision(page, arguments);
              } else {
                arguments->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
              }
              return S_OK;
            })
            .Get(),
        &tokens.certificate_error);
  }

  webview->CallDevToolsProtocolMethod(
      L"Log.enable", L"{}",
      Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
          [](HRESULT, LPCWSTR) { return S_OK; })
          .Get());
  if (SUCCEEDED(webview->GetDevToolsProtocolEventReceiver(
          L"Log.entryAdded",
          page->console_receiver().ReleaseAndGetAddressOf()))) {
    page->console_receiver()->add_DevToolsProtocolEventReceived(
        Callback<ICoreWebView2DevToolsProtocolEventReceivedEventHandler>(
            [weak](
                ICoreWebView2*,
                ICoreWebView2DevToolsProtocolEventReceivedEventArgs*
                    arguments) {
              const auto page = weak.lock();
              LPWSTR raw = nullptr;
              if (page &&
                  SUCCEEDED(arguments->get_ParameterObjectAsJson(&raw)) &&
                  raw != nullptr) {
                const auto event = ConsoleEvent(*page, Utf8(raw));
                if (event.has_value()) {
                  page->plugin()->Emit(*event);
                }
                CoTaskMemFree(raw);
              }
              return S_OK;
            })
            .Get(),
        &tokens.console_entry);
  }
}

void UnregisterBrowserPageEvents(BrowserPage* page) {
  auto* webview = page->webview();
  if (webview == nullptr) {
    return;
  }
  const auto& tokens = page->event_tokens();
  webview->remove_NavigationStarting(tokens.navigation_starting);
  webview->remove_ContentLoading(tokens.content_loading);
  webview->remove_NavigationCompleted(tokens.navigation_completed);
  webview->remove_SourceChanged(tokens.source_changed);
  webview->remove_DocumentTitleChanged(tokens.title_changed);
  webview->remove_WindowCloseRequested(
      tokens.window_close_requested);
  webview->remove_PermissionRequested(tokens.permission_requested);
  webview->remove_NewWindowRequested(tokens.new_window_requested);
  ComPtr<ICoreWebView2_4> webview4;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview4)))) {
    webview4->remove_DownloadStarting(tokens.download_starting);
  }
  ComPtr<ICoreWebView2_14> webview14;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview14)))) {
    webview14->remove_ServerCertificateErrorDetected(
        tokens.certificate_error);
  }
  if (page->console_receiver()) {
    page->console_receiver()->remove_DevToolsProtocolEventReceived(
        tokens.console_entry);
  }
}

}  // namespace alera_browser
