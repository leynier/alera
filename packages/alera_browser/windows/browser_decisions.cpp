#include "alera_browser_plugin.h"

#include "browser_decision_timeout.h"
#include "browser_page.h"
#include "browser_value.h"

#include <wrl/client.h>

#include <map>
#include <utility>

namespace alera_browser {
using Microsoft::WRL::ComPtr;

namespace {

std::map<UINT_PTR, std::pair<AleraBrowserPlugin*, std::string>>
    g_decision_timers;

void CALLBACK DecisionTimeout(
    HWND,
    UINT,
    UINT_PTR timer_id,
    DWORD) {
  const auto iterator = g_decision_timers.find(timer_id);
  if (iterator == g_decision_timers.end()) {
    return;
  }
  auto [plugin, decision_id] = iterator->second;
  g_decision_timers.erase(iterator);
  KillTimer(nullptr, timer_id);
  plugin->ExpireDecision(decision_id);
}

std::string PermissionName(COREWEBVIEW2_PERMISSION_KIND kind) {
  switch (kind) {
    case COREWEBVIEW2_PERMISSION_KIND_MICROPHONE:
      return "microphone";
    case COREWEBVIEW2_PERMISSION_KIND_CAMERA:
      return "camera";
    case COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION:
      return "geolocation";
    case COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS:
      return "notifications";
    case COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS:
      return "sensors";
    case COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ:
      return "clipboardRead";
    default:
      return "unknown";
  }
}

}  // namespace

std::string AleraBrowserPlugin::RegisterDecision(
    BrowserDecisionKind kind,
    const std::string& page_id,
    std::function<void(const EncodableMap&)> resolve,
    std::function<void()> deny) {
  const auto id = "decision-" + std::to_string(next_decision_id_++);
  auto [iterator, inserted] = decisions_.emplace(
      id,
      PendingBrowserDecision{
          kind, page_id, std::move(resolve), std::move(deny)});
  if (!inserted) {
    return {};
  }
  const UINT_PTR timer_id =
      SetTimer(
          nullptr, 0, kBrowserDecisionTimeoutMilliseconds,
          DecisionTimeout);
  if (timer_id == 0) {
    auto failed = std::move(iterator->second);
    decisions_.erase(iterator);
    failed.deny();
    return {};
  }
  iterator->second.timer_id = timer_id;
  g_decision_timers[timer_id] = {this, id};
  return id;
}

void CancelBrowserDecisionTimeout(PendingBrowserDecision* decision) {
  if (decision == nullptr || decision->timer_id == 0) {
    return;
  }
  KillTimer(nullptr, decision->timer_id);
  g_decision_timers.erase(decision->timer_id);
  decision->timer_id = 0;
}

void AleraBrowserPlugin::ResolveDecision(
    const EncodableMap& arguments,
    MethodResultPtr result) {
  const auto id = StringValue(arguments, "decisionId");
  if (!id.has_value()) {
    Error(
        std::move(result), "invalid_decision",
        "A browser decision id is required.");
    return;
  }
  const auto iterator = decisions_.find(*id);
  if (iterator == decisions_.end()) {
    Error(
        std::move(result), "stale_decision",
        "The browser decision is no longer pending.");
    return;
  }
  auto decision = std::move(iterator->second);
  decisions_.erase(iterator);
  CancelBrowserDecisionTimeout(&decision);
  decision.resolve(arguments);
  Success(std::move(result));
}

void AleraBrowserPlugin::ExpireDecision(
    const std::string& decision_id) {
  const auto iterator = decisions_.find(decision_id);
  if (iterator == decisions_.end()) {
    return;
  }
  auto decision = std::move(iterator->second);
  decisions_.erase(iterator);
  decision.timer_id = 0;
  decision.deny();
}

void AleraBrowserPlugin::StartPermissionDecision(
    const std::shared_ptr<BrowserPage>& page,
    ICoreWebView2PermissionRequestedEventArgs* arguments) {
  COREWEBVIEW2_PERMISSION_KIND kind =
      COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
  LPWSTR raw_origin = nullptr;
  arguments->get_PermissionKind(&kind);
  arguments->get_Uri(&raw_origin);
  const std::string permission = PermissionName(kind);
  const std::string origin = Utf8(raw_origin);
  CoTaskMemFree(raw_origin);
  if (!event_sink_ || permission == "unknown" ||
      !IsAllowedBrowserUrl(origin)) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }
  ComPtr<ICoreWebView2PermissionRequestedEventArgs3> arguments3;
  if (FAILED(arguments->QueryInterface(IID_PPV_ARGS(&arguments3))) ||
      FAILED(arguments3->put_SavesInProfile(FALSE))) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }

  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(arguments->GetDeferral(&deferral)) || !deferral) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }
  ComPtr<ICoreWebView2PermissionRequestedEventArgs> held_arguments =
      arguments;
  auto complete =
      [held_arguments, deferral](bool allow) {
        held_arguments->put_State(
            allow ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
                  : COREWEBVIEW2_PERMISSION_STATE_DENY);
        deferral->Complete();
      };
  const auto decision_id = RegisterDecision(
      BrowserDecisionKind::permission, page->id(),
      [complete](const EncodableMap& value) {
        complete(StringValue(value, "decision").value_or("deny") == "allow");
      },
      [complete]() { complete(false); });
  if (decision_id.empty()) {
    return;
  }
  auto event = BrowserEvent("permissionRequest", page->id());
  event[EncodableValue("decisionId")] = EncodableValue(decision_id);
  event[EncodableValue("origin")] = EncodableValue(origin);
  event[EncodableValue("resources")] =
      EncodableValue(flutter::EncodableList{EncodableValue(permission)});
  Emit(std::move(event));
}

void AleraBrowserPlugin::StartTlsDecision(
    const std::shared_ptr<BrowserPage>& page,
    ICoreWebView2ServerCertificateErrorDetectedEventArgs* arguments) {
  (void)page;
  arguments->put_Action(
      COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
}

}  // namespace alera_browser
