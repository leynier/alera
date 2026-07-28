#ifndef ALERA_BROWSER_WINDOWS_BROWSER_PAGE_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_PAGE_H_

#include <WebView2.h>
#include <wrl/client.h>

#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>

namespace alera_browser {

class AleraBrowserPlugin;
class BrowserProfile;

class BrowserPage : public std::enable_shared_from_this<BrowserPage> {
 public:
  using CreatedCallback =
      std::function<void(HRESULT, std::shared_ptr<BrowserPage>)>;
  using ScriptCallback =
      std::function<void(HRESULT, std::string)>;

  static void Create(
      AleraBrowserPlugin* plugin,
      HWND parent_window,
      std::shared_ptr<BrowserProfile> profile,
      std::string id,
      std::optional<std::string> initial_url,
      std::optional<std::string> user_agent,
      std::optional<std::string> opener_page_id,
      bool transient,
      CreatedCallback callback);

  ~BrowserPage();
  BrowserPage(const BrowserPage&) = delete;
  BrowserPage& operator=(const BrowserPage&) = delete;

  const std::string& id() const { return id_; }
  const std::string& profile_id() const;
  const std::optional<std::string>& opener_page_id() const {
    return opener_page_id_;
  }
  bool transient() const { return transient_; }
  bool adopted() const { return adopted_; }
  bool attached() const { return attached_; }
  AleraBrowserPlugin* plugin() const { return plugin_; }
  ICoreWebView2* webview() const { return webview_.Get(); }
  ICoreWebView2Environment* environment() const;

  void SetAdopted(bool adopted) { adopted_ = adopted; }
  void Promote() { transient_ = false; }
  void SetAttached(bool attached);
  void SetObscured(bool obscured);
  void SetBounds(double x, double y, double width, double height, double scale);
  void Navigate(
      const std::string& url,
      const std::map<std::string, std::string>& headers,
      std::function<void(HRESULT)> callback);
  void ExecuteScript(const std::string& script, ScriptCallback callback);
  std::optional<std::string> CurrentUrl() const;
  std::optional<std::string> Title() const;
  bool CanGoBack() const;
  bool CanGoForward() const;
  HRESULT GoBack();
  HRESULT GoForward();
  HRESULT Reload();
  HRESULT Stop();
  void Close();

  struct EventTokens {
    EventRegistrationToken navigation_starting{};
    EventRegistrationToken content_loading{};
    EventRegistrationToken navigation_completed{};
    EventRegistrationToken source_changed{};
    EventRegistrationToken title_changed{};
    EventRegistrationToken window_close_requested{};
    EventRegistrationToken permission_requested{};
    EventRegistrationToken new_window_requested{};
    EventRegistrationToken download_starting{};
    EventRegistrationToken certificate_error{};
    EventRegistrationToken console_entry{};
  };

  EventTokens& event_tokens() { return event_tokens_; }
  Microsoft::WRL::ComPtr<ICoreWebView2DevToolsProtocolEventReceiver>&
  console_receiver() {
    return console_receiver_;
  }

 private:
  BrowserPage(
      AleraBrowserPlugin* plugin,
      std::shared_ptr<BrowserProfile> profile,
      std::string id,
      std::optional<std::string> initial_url,
      std::optional<std::string> user_agent,
      std::optional<std::string> opener_page_id,
      bool transient);
  void FinishCreate(
      HWND parent_window,
      HRESULT result,
      ICoreWebView2Controller* controller,
      CreatedCallback callback);
  void UpdateVisibility();
  void RegisterEvents();
  void UnregisterEvents();

  AleraBrowserPlugin* plugin_;
  std::shared_ptr<BrowserProfile> profile_;
  std::string id_;
  std::optional<std::string> initial_url_;
  std::optional<std::string> user_agent_;
  std::optional<std::string> opener_page_id_;
  bool transient_;
  bool adopted_;
  bool attached_ = false;
  bool obscured_ = false;
  bool closed_ = false;
  double x_ = 0;
  double y_ = 0;
  double width_ = 0;
  double height_ = 0;
  double scale_ = 1;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
  Microsoft::WRL::ComPtr<ICoreWebView2DevToolsProtocolEventReceiver>
      console_receiver_;
  EventTokens event_tokens_;
};

void RegisterBrowserPageEvents(const std::shared_ptr<BrowserPage>& page);
void UnregisterBrowserPageEvents(BrowserPage* page);

}  // namespace alera_browser

#endif
