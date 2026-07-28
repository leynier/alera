#ifndef ALERA_BROWSER_WINDOWS_BROWSER_PLATFORM_DISPATCHER_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_PLATFORM_DISPATCHER_H_

#include <windows.h>

#include <deque>
#include <functional>
#include <memory>
#include <mutex>

namespace alera_browser {

class BrowserPlatformDispatcher {
 public:
  using Task = std::function<void()>;
  static constexpr UINT kMessage = WM_APP + 0x3a7;

  explicit BrowserPlatformDispatcher(HWND view_window);
  BrowserPlatformDispatcher(const BrowserPlatformDispatcher&) = delete;
  BrowserPlatformDispatcher& operator=(
      const BrowserPlatformDispatcher&) = delete;

  bool Post(Task task);
  void Drain();
  void Close();

 private:
  HWND target_window_;
  std::mutex mutex_;
  std::deque<std::shared_ptr<Task>> tasks_;
  bool closed_ = false;
};

}  // namespace alera_browser

#endif
