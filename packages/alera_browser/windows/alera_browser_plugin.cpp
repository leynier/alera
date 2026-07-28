#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_platform_dispatcher.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <flutter/event_stream_handler_functions.h>

#include <filesystem>
#include <optional>
#include <utility>
#include <vector>

namespace alera_browser {

void AleraBrowserPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<AleraBrowserPlugin>(registrar);
  auto* plugin_pointer = plugin.get();

  plugin->method_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "dev.leynier.alera/browser",
          &flutter::StandardMethodCodec::GetInstance());
  plugin->method_channel_->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  plugin->event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "dev.leynier.alera/browser/events",
          &flutter::StandardMethodCodec::GetInstance());
  plugin->event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [plugin_pointer](
              const EncodableValue*,
              std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) {
            plugin_pointer->event_sink_ = std::move(sink);
            return nullptr;
          },
          [plugin_pointer](const EncodableValue*) {
            plugin_pointer->event_sink_.reset();
            plugin_pointer->DenyAllDecisions();
            return nullptr;
          }));
  registrar->AddPlugin(std::move(plugin));
}

AleraBrowserPlugin::AleraBrowserPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      parent_window_(
          registrar->GetView() == nullptr
              ? nullptr
              : registrar->GetView()->GetNativeWindow()) {
  dispatcher_ =
      std::make_shared<BrowserPlatformDispatcher>(parent_window_);
  const auto weak_dispatcher =
      std::weak_ptr<BrowserPlatformDispatcher>(dispatcher_);
  window_proc_delegate_id_ =
      registrar_->RegisterTopLevelWindowProcDelegate(
          [weak_dispatcher](
              HWND,
              UINT message,
              WPARAM,
              LPARAM) -> std::optional<LRESULT> {
            if (message != BrowserPlatformDispatcher::kMessage) {
              return std::nullopt;
            }
            if (const auto dispatcher = weak_dispatcher.lock()) {
              dispatcher->Drain();
            }
            return LRESULT{0};
          });
  const auto root = BrowserProfileRoot();
  std::error_code error;
  std::filesystem::create_directories(root, error);
  profiles_["default"] = std::make_shared<BrowserProfile>(
      "default", false, root / L"default");
  for (const auto& entry :
       std::filesystem::directory_iterator(root, error)) {
    std::error_code entry_error;
    if (!entry.is_directory(entry_error)) {
      continue;
    }
    const auto id = Utf8(entry.path().filename().wstring());
    if (id == "default" || !IsValidBrowserId(id)) {
      continue;
    }
    profiles_[id] = std::make_shared<BrowserProfile>(
        id, false, entry.path());
  }
}

AleraBrowserPlugin::~AleraBrowserPlugin() {
  dispatcher_->Close();
  registrar_->UnregisterTopLevelWindowProcDelegate(
      window_proc_delegate_id_);
  lifetime_.reset();
  DenyAllDecisions();
  pages_.clear();
  profiles_.clear();
  dispatcher_.reset();
}

std::shared_ptr<BrowserPage> AleraBrowserPlugin::FindPage(
    const std::string& page_id) const {
  const auto iterator = pages_.find(page_id);
  return iterator == pages_.end() ? nullptr : iterator->second;
}

std::shared_ptr<BrowserProfile> AleraBrowserPlugin::FindProfile(
    const std::string& profile_id) const {
  const auto iterator = profiles_.find(profile_id);
  return iterator == profiles_.end() ? nullptr : iterator->second;
}

bool AleraBrowserPlugin::AddPage(
    const std::shared_ptr<BrowserPage>& page) {
  return pages_.emplace(page->id(), page).second;
}

void AleraBrowserPlugin::RemovePage(const std::string& page_id) {
  auto page = FindPage(page_id);
  if (page) {
    page->Close();
    pages_.erase(page_id);
  }
  std::vector<PendingBrowserDecision> removed;
  for (auto iterator = decisions_.begin(); iterator != decisions_.end();) {
    if (iterator->second.page_id == page_id) {
      removed.push_back(std::move(iterator->second));
      iterator = decisions_.erase(iterator);
    } else {
      ++iterator;
    }
  }
  for (auto& decision : removed) {
    CancelBrowserDecisionTimeout(&decision);
    decision.deny();
  }
}

void AleraBrowserPlugin::Emit(EncodableMap event) {
  if (event_sink_) {
    event_sink_->Success(EncodableValue(std::move(event)));
  }
}

void AleraBrowserPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    MethodResultPtr result) {
  const auto* arguments_value = method_call.arguments();
  const auto* arguments = arguments_value == nullptr
                              ? nullptr
                              : std::get_if<EncodableMap>(arguments_value);
  const EncodableMap empty;
  const auto& values = arguments == nullptr ? empty : *arguments;
  const auto& method = method_call.method_name();
  if (method == "probe") {
    HandleProbe(std::move(result));
  } else if (method == "decision.resolve") {
    ResolveDecision(values, std::move(result));
  } else if (method.rfind("profile.", 0) == 0) {
    HandleBrowserProfileMethod(this, method, values, std::move(result));
  } else if (method.rfind("page.", 0) == 0) {
    HandleBrowserPageMethod(this, method, values, std::move(result));
  } else if (method.rfind("cookies.", 0) == 0) {
    HandleBrowserCookieMethod(this, method, values, std::move(result));
  } else if (method.rfind("capture.", 0) == 0) {
    HandleBrowserCaptureMethod(this, method, values, std::move(result));
  } else if (method.rfind("cookieImport.", 0) == 0) {
    HandleBrowserImportMethod(this, method, values, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void AleraBrowserPlugin::HandleProbe(MethodResultPtr result) {
  LPWSTR raw_version = nullptr;
  const HRESULT probe =
      GetAvailableCoreWebView2BrowserVersionString(nullptr, &raw_version);
  const bool available =
      SUCCEEDED(probe) && raw_version != nullptr && parent_window_ != nullptr;
  const std::string version = raw_version == nullptr ? "" : Utf8(raw_version);
  CoTaskMemFree(raw_version);

  EncodableMap value{
      {EncodableValue("engine"), EncodableValue("webView2")},
      {EncodableValue("engineVersion"), EncodableValue(version)},
  };
  const char* required_flags[] = {
      "engineAvailable",
      "pageSurface",
      "isolatedProfiles",
      "ephemeralProfiles",
      "deterministicPageClose",
      "navigation",
      "navigationEvents",
      "javascript",
      "basicCookies",
      "fullCookies",
      "permissionCallbacks",
      "tlsCallbacks",
      "popupCallbacks",
      "downloadCallbacks",
      "domSnapshot",
      "domActions",
      "viewportScreenshot",
      "fullPageScreenshot",
      "pdf",
      "flutterOverlayOcclusion",
      "atomicCookieImport",
      "manualJsonCookieImport",
  };
  for (const auto* flag : required_flags) {
    value[EncodableValue(flag)] = EncodableValue(available);
  }
  value[EncodableValue("tlsTrustScope")] =
      EncodableValue(available ? "profileSession" : "none");
  value[EncodableValue("crossOriginFrameAutomation")] =
      EncodableValue(false);
  value[EncodableValue("nativeFileUpload")] = EncodableValue(false);
  value[EncodableValue("trustedInputEvents")] = EncodableValue(false);
  const flutter::EncodableList native_sources{
      EncodableValue("chrome"), EncodableValue("edge"),
      EncodableValue("brave"), EncodableValue("comet"),
      EncodableValue("firefox")};
  value[EncodableValue("nativeCookieImportSources")] =
      EncodableValue(
          available ? native_sources : flutter::EncodableList());
  value[EncodableValue("requiredNativeCookieImportSources")] =
      EncodableValue(native_sources);
  flutter::EncodableList limitations{
      EncodableValue("cross_origin_frames_unavailable"),
      EncodableValue("native_file_upload_unavailable"),
      EncodableValue("trusted_input_events_unavailable"),
      EncodableValue("popup_opener_requirement_unavailable"),
      EncodableValue("screenshot_scale_unavailable"),
      EncodableValue("chromium_app_bound_cookie_import_unavailable")};
  if (!available) {
    limitations.emplace_back("webview2_evergreen_unavailable");
  }
  value[EncodableValue("limitations")] =
      EncodableValue(std::move(limitations));
  Success(std::move(result), EncodableValue(std::move(value)));
}

void AleraBrowserPlugin::DenyAllDecisions() {
  auto pending = std::move(decisions_);
  decisions_.clear();
  for (auto& entry : pending) {
    auto& decision = entry.second;
    CancelBrowserDecisionTimeout(&decision);
    decision.deny();
  }
}

}  // namespace alera_browser
