#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_value.h"

#include <wrl.h>
#include <wrl/client.h>

#include <memory>
#include <optional>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

struct DownloadObserver {
  AleraBrowserPlugin* plugin;
  std::weak_ptr<int> lifetime;
  std::string page_id;
  std::string download_id;
  std::string suggested_file_name;
  std::string destination_path;
  ComPtr<ICoreWebView2DownloadOperation> operation;
  EventRegistrationToken bytes_token{};
  EventRegistrationToken state_token{};

  void Emit(
      const std::string& state,
      const std::optional<std::string>& error_code = std::nullopt) {
    if (lifetime.expired() || !operation) {
      return;
    }
    INT64 received = 0;
    INT64 total = 0;
    operation->get_BytesReceived(&received);
    operation->get_TotalBytesToReceive(&total);
    auto event = BrowserEvent("downloadChanged", page_id);
    event[EncodableValue("downloadId")] =
        EncodableValue(download_id);
    event[EncodableValue("state")] = EncodableValue(state);
    event[EncodableValue("suggestedFileName")] =
        EncodableValue(suggested_file_name);
    event[EncodableValue("destinationPath")] =
        EncodableValue(destination_path);
    event[EncodableValue("receivedBytes")] = EncodableValue(received);
    if (total >= 0) {
      event[EncodableValue("totalBytes")] = EncodableValue(total);
    }
    if (error_code.has_value()) {
      event[EncodableValue("errorCode")] =
          EncodableValue(*error_code);
    }
    plugin->Emit(std::move(event));
  }
};

void ObserveDownload(
    AleraBrowserPlugin* plugin,
    const std::string& page_id,
    const std::string& download_id,
    const std::string& suggested_file_name,
    const std::string& destination_path,
    ICoreWebView2DownloadOperation* operation) {
  auto observer = std::make_shared<DownloadObserver>(
      DownloadObserver{
          plugin, plugin->lifetime(), page_id, download_id,
          suggested_file_name, destination_path, operation});
  operation->add_BytesReceivedChanged(
      Callback<ICoreWebView2BytesReceivedChangedEventHandler>(
          [observer](ICoreWebView2DownloadOperation*, IUnknown*) {
            observer->Emit("inProgress");
            return S_OK;
          })
          .Get(),
      &observer->bytes_token);
  operation->add_StateChanged(
      Callback<ICoreWebView2StateChangedEventHandler>(
          [observer](ICoreWebView2DownloadOperation*, IUnknown*) {
            COREWEBVIEW2_DOWNLOAD_STATE state =
                COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS;
            observer->operation->get_State(&state);
            if (state == COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS) {
              observer->Emit("inProgress");
              return S_OK;
            }
            if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED) {
              observer->Emit("completed");
            } else {
              COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON reason =
                  COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_NONE;
              observer->operation->get_InterruptReason(&reason);
              const bool cancelled =
                  reason ==
                  COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_USER_CANCELED;
              observer->Emit(
                  cancelled ? "cancelled" : "failed",
                  "webview2_" +
                      std::to_string(static_cast<int>(reason)));
            }
            observer->operation->remove_BytesReceivedChanged(
                observer->bytes_token);
            observer->operation->remove_StateChanged(
                observer->state_token);
            observer->operation.Reset();
            return S_OK;
          })
          .Get(),
      &observer->state_token);
}

}  // namespace

void AleraBrowserPlugin::StartDownloadDecision(
    const std::shared_ptr<BrowserPage>& page,
    ICoreWebView2DownloadStartingEventArgs* arguments) {
  ComPtr<ICoreWebView2DownloadOperation> operation;
  arguments->get_DownloadOperation(&operation);
  if (!operation) {
    arguments->put_Cancel(TRUE);
    return;
  }
  arguments->put_Handled(TRUE);
  LPWSTR raw_url = nullptr;
  LPWSTR raw_mime = nullptr;
  LPWSTR raw_path = nullptr;
  INT64 total = 0;
  operation->get_Uri(&raw_url);
  operation->get_MimeType(&raw_mime);
  operation->get_TotalBytesToReceive(&total);
  arguments->get_ResultFilePath(&raw_path);
  const std::string url = Utf8(raw_url);
  const std::string mime = Utf8(raw_mime);
  const std::string suggested = FileName(Utf16(Utf8(raw_path)));
  CoTaskMemFree(raw_url);
  CoTaskMemFree(raw_mime);
  CoTaskMemFree(raw_path);
  if (!event_sink_ || !IsAllowedBrowserUrl(url)) {
    arguments->put_Cancel(TRUE);
    return;
  }

  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(arguments->GetDeferral(&deferral)) || !deferral) {
    arguments->put_Cancel(TRUE);
    return;
  }
  ComPtr<ICoreWebView2DownloadStartingEventArgs> held_arguments =
      arguments;
  const auto complete =
      [this, held_arguments, deferral, operation, page, suggested](
          const std::optional<std::string>& destination,
          const std::string& download_id) {
        if (destination.has_value() &&
            IsAbsoluteFilePath(*destination)) {
          held_arguments->put_ResultFilePath(
              Utf16(*destination).c_str());
          held_arguments->put_Cancel(FALSE);
          ObserveDownload(
              this, page->id(), download_id, suggested,
              *destination, operation.Get());
        } else {
          held_arguments->put_Cancel(TRUE);
        }
        deferral->Complete();
      };
  auto decision_id = std::make_shared<std::string>();
  *decision_id = RegisterDecision(
      BrowserDecisionKind::download, page->id(),
      [complete, decision_id](const EncodableMap& value) {
        const bool accepted =
            StringValue(value, "decision").value_or("deny") == "accept";
        complete(
            accepted ? StringValue(value, "destinationPath")
                     : std::nullopt,
            *decision_id);
      },
      [complete, decision_id]() {
        complete(std::nullopt, *decision_id);
      });
  if (decision_id->empty()) {
    return;
  }
  auto event = BrowserEvent("downloadRequest", page->id());
  event[EncodableValue("decisionId")] = EncodableValue(*decision_id);
  event[EncodableValue("url")] = EncodableValue(url);
  event[EncodableValue("mimeType")] = EncodableValue(mime);
  event[EncodableValue("suggestedFileName")] =
      EncodableValue(suggested);
  if (total >= 0) {
    event[EncodableValue("totalBytes")] = EncodableValue(total);
  }
  Emit(std::move(event));
}

}  // namespace alera_browser
