#ifndef RUNNER_WIN32_DESKTOP_PRESENCE_H_
#define RUNNER_WIN32_DESKTOP_PRESENCE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

class Win32DesktopPresence {
 public:
  Win32DesktopPresence();
  ~Win32DesktopPresence();

  void Attach(
      HWND hwnd,
      flutter::MethodChannel<flutter::EncodableValue>* channel);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void Destroy();

 private:
  bool SetTray(bool visible, const std::wstring& tooltip);
  void SetBadgeCount(int count);
  void ShowFromTray();
  void QuitFromTray();
  void NotifyInstallation(bool installed);
  HICON CreateBadgeIcon(int count);
  void UpdateOverlay();

  HWND hwnd_ = nullptr;
  flutter::MethodChannel<flutter::EncodableValue>* channel_ = nullptr;
  NOTIFYICONDATA nid_{};
  bool tray_desired_ = false;
  bool tray_visible_ = false;
  std::wstring tooltip_;
  int badge_count_ = 0;
  HICON overlay_icon_ = nullptr;
  HICON tray_icon_ = nullptr;
  UINT taskbar_button_created_message_ = 0;
  UINT taskbar_created_message_ = 0;
};

#endif  // RUNNER_WIN32_DESKTOP_PRESENCE_H_
