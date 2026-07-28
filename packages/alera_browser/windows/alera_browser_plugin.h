#ifndef FLUTTER_PLUGIN_ALERA_BROWSER_PLUGIN_H_
#define FLUTTER_PLUGIN_ALERA_BROWSER_PLUGIN_H_

#include <WebView2.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>

namespace alera_browser {

class BrowserPage;
class BrowserPlatformDispatcher;
class BrowserProfile;

using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;
using MethodResult = flutter::MethodResult<EncodableValue>;
using MethodResultPtr = std::unique_ptr<MethodResult>;

enum class BrowserDecisionKind { permission, tls, popup, download };

struct PendingBrowserDecision {
  BrowserDecisionKind kind;
  std::string page_id;
  std::function<void(const EncodableMap&)> resolve;
  std::function<void()> deny;
  UINT_PTR timer_id = 0;
};

class AleraBrowserPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit AleraBrowserPlugin(flutter::PluginRegistrarWindows* registrar);
  ~AleraBrowserPlugin() override;
  AleraBrowserPlugin(const AleraBrowserPlugin&) = delete;
  AleraBrowserPlugin& operator=(const AleraBrowserPlugin&) = delete;

  HWND parent_window() const { return parent_window_; }
  std::weak_ptr<int> lifetime() const { return lifetime_; }
  std::shared_ptr<BrowserPlatformDispatcher> dispatcher() const {
    return dispatcher_;
  }
  std::shared_ptr<BrowserPage> FindPage(const std::string& page_id) const;
  std::shared_ptr<BrowserProfile> FindProfile(
      const std::string& profile_id) const;
  bool AddPage(const std::shared_ptr<BrowserPage>& page);
  void RemovePage(const std::string& page_id);
  void Emit(EncodableMap event);

  std::string RegisterDecision(
      BrowserDecisionKind kind,
      const std::string& page_id,
      std::function<void(const EncodableMap&)> resolve,
      std::function<void()> deny);
  void ResolveDecision(const EncodableMap& arguments, MethodResultPtr result);
  void ExpireDecision(const std::string& decision_id);
  void StartPopupDecision(
      const std::shared_ptr<BrowserPage>& opener,
      ICoreWebView2NewWindowRequestedEventArgs* arguments);
  void StartPermissionDecision(
      const std::shared_ptr<BrowserPage>& page,
      ICoreWebView2PermissionRequestedEventArgs* arguments);
  void StartTlsDecision(
      const std::shared_ptr<BrowserPage>& page,
      ICoreWebView2ServerCertificateErrorDetectedEventArgs* arguments);
  void StartDownloadDecision(
      const std::shared_ptr<BrowserPage>& page,
      ICoreWebView2DownloadStartingEventArgs* arguments);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& method_call,
      MethodResultPtr result);
  void HandleProbe(MethodResultPtr result);
  void DenyAllDecisions();

  flutter::PluginRegistrarWindows* registrar_;
  HWND parent_window_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;
  std::shared_ptr<int> lifetime_ = std::make_shared<int>(0);
  std::shared_ptr<BrowserPlatformDispatcher> dispatcher_;
  int window_proc_delegate_id_ = 0;
  std::map<std::string, std::shared_ptr<BrowserProfile>> profiles_;
  std::map<std::string, std::shared_ptr<BrowserPage>> pages_;
  std::map<std::string, PendingBrowserDecision> decisions_;
  std::set<std::string> active_cookie_imports_;
  uint64_t next_page_id_ = 1;
  uint64_t next_decision_id_ = 1;

  friend bool HandleBrowserProfileMethod(
      AleraBrowserPlugin*,
      const std::string&,
      const EncodableMap&,
      MethodResultPtr);
  friend bool HandleBrowserPageMethod(
      AleraBrowserPlugin*,
      const std::string&,
      const EncodableMap&,
      MethodResultPtr);
  friend bool HandleBrowserImportMethod(
      AleraBrowserPlugin*,
      const std::string&,
      const EncodableMap&,
      MethodResultPtr);
};

bool HandleBrowserProfileMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result);
bool HandleBrowserPageMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result);
bool HandleBrowserCookieMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result);
bool HandleBrowserCaptureMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result);
bool HandleBrowserImportMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result);
void CancelBrowserDecisionTimeout(PendingBrowserDecision* decision);

}  // namespace alera_browser

#endif
