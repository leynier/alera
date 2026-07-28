#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <wrl/client.h>

#include <memory>

namespace alera_browser {
namespace {

using Microsoft::WRL::ComPtr;

struct PopupDecisionState {
  AleraBrowserPlugin* plugin;
  ComPtr<ICoreWebView2NewWindowRequestedEventArgs> arguments;
  ComPtr<ICoreWebView2Deferral> deferral;
  std::shared_ptr<BrowserPage> page;
  bool completed = false;

  void Complete(bool allow) {
    if (completed) {
      return;
    }
    completed = true;
    if (allow && page && page->adopted()) {
      arguments->put_NewWindow(page->webview());
    } else if (page) {
      plugin->RemovePage(page->id());
      page.reset();
    }
    arguments->put_Handled(TRUE);
    deferral->Complete();
  }
};

}  // namespace

void AleraBrowserPlugin::StartPopupDecision(
    const std::shared_ptr<BrowserPage>& opener,
    ICoreWebView2NewWindowRequestedEventArgs* arguments) {
  LPWSTR raw_url = nullptr;
  BOOL user_initiated = FALSE;
  arguments->get_Uri(&raw_url);
  arguments->get_IsUserInitiated(&user_initiated);
  const std::string url = Utf8(raw_url);
  CoTaskMemFree(raw_url);
  std::string window_name;
  ComPtr<ICoreWebView2NewWindowRequestedEventArgs2> arguments2;
  if (SUCCEEDED(arguments->QueryInterface(IID_PPV_ARGS(&arguments2)))) {
    LPWSTR raw_name = nullptr;
    if (SUCCEEDED(arguments2->get_Name(&raw_name)) &&
        raw_name != nullptr) {
      window_name = Utf8(raw_name);
      CoTaskMemFree(raw_name);
    }
  }
  if (!event_sink_ || !IsAllowedBrowserUrl(url)) {
    arguments->put_Handled(TRUE);
    return;
  }

  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(arguments->GetDeferral(&deferral)) || !deferral) {
    arguments->put_Handled(TRUE);
    return;
  }
  const auto transient_id =
      "popup-" + std::to_string(next_page_id_++);
  auto state = std::make_shared<PopupDecisionState>(
      PopupDecisionState{this, arguments, deferral});
  const auto decision_id = RegisterDecision(
      BrowserDecisionKind::popup, opener->id(),
      [state, transient_id](const EncodableMap& value) {
        const bool accepted =
            StringValue(value, "decision").value_or("deny") ==
                "newPage" &&
            StringValue(value, "targetPageId").value_or("") ==
                transient_id;
        state->Complete(accepted);
      },
      [state]() { state->Complete(false); });
  if (decision_id.empty()) {
    return;
  }

  const auto profile = FindProfile(opener->profile_id());
  BrowserPage::Create(
      this, parent_window_, profile, transient_id, std::nullopt,
      std::nullopt, opener->id(), true,
      [this, opener, state, decision_id, transient_id, url,
       window_name, user_initiated](
          HRESULT created,
          std::shared_ptr<BrowserPage> page) {
        if (state->completed) {
          if (page) {
            page->Close();
          }
          return;
        }
        if (FAILED(created) || !page || !AddPage(page) || !event_sink_) {
          if (page) {
            page->Close();
          }
          const auto iterator = decisions_.find(decision_id);
          if (iterator != decisions_.end()) {
            auto decision = std::move(iterator->second);
            decisions_.erase(iterator);
            CancelBrowserDecisionTimeout(&decision);
            decision.deny();
          }
          return;
        }
        state->page = page;
        auto event = BrowserEvent("popupRequest", opener->id());
        event[EncodableValue("decisionId")] =
            EncodableValue(decision_id);
        event[EncodableValue("transientPageId")] =
            EncodableValue(transient_id);
        event[EncodableValue("profileId")] =
            EncodableValue(opener->profile_id());
        event[EncodableValue("url")] = EncodableValue(url);
        event[EncodableValue("windowName")] =
            EncodableValue(window_name);
        event[EncodableValue("userInitiated")] =
            EncodableValue(user_initiated == TRUE);
        event[EncodableValue("trusted")] =
            EncodableValue(user_initiated == TRUE);
        event[EncodableValue("requiresOpener")] = EncodableValue(false);
        Emit(std::move(event));
      });
}

}  // namespace alera_browser
