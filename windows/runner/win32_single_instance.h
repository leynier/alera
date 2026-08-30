#ifndef RUNNER_WIN32_SINGLE_INSTANCE_H_
#define RUNNER_WIN32_SINGLE_INSTANCE_H_

#include <windows.h>

#include <string>

// Owned by the startup thread until the Flutter window has been destroyed.
class Win32SingleInstance {
 public:
  enum class StartResult { primary, forwarded, failed };

  explicit Win32SingleInstance(const std::wstring& app_id);
  ~Win32SingleInstance();
  Win32SingleInstance(const Win32SingleInstance&) = delete;
  Win32SingleInstance& operator=(const Win32SingleInstance&) = delete;

  StartResult Start();
  int RunMessageLoop(HWND window);

 private:
  static BOOL CALLBACK AllowForegroundForWindow(HWND window, LPARAM context);

  const std::wstring object_name_;
  const std::wstring window_property_;
  HANDLE mutex_ = nullptr;
  HANDLE activation_event_ = nullptr;
  bool owns_mutex_ = false;
};

#endif  // RUNNER_WIN32_SINGLE_INSTANCE_H_
