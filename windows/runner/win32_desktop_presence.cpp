#include "win32_desktop_presence.h"

#include <shellapi.h>
#include <shobjidl.h>

#include <string>

#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayCallback = WM_APP + 40;
constexpr UINT kTrayShowId = 1;
constexpr UINT kTrayQuitId = 2;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size =
      ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), size);
  if (!wide.empty() && wide.back() == L'\0') {
    wide.pop_back();
  }
  return wide;
}

std::wstring BadgeLabel(int count) {
  if (count <= 0) {
    return L"";
  }
  if (count > 9) {
    return L"9+";
  }
  return std::to_wstring(count);
}

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return std::get_if<flutter::EncodableMap>(value);
}

bool MapBool(const flutter::EncodableMap& map, const char* key, bool fallback) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* flag = std::get_if<bool>(&it->second)) {
    return *flag;
  }
  return fallback;
}

int MapInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

std::string MapString(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::string();
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return std::string();
}

}  // namespace

Win32DesktopPresence::Win32DesktopPresence() {
  taskbar_button_created_message_ =
      ::RegisterWindowMessageW(L"TaskbarButtonCreated");
  taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");
}

Win32DesktopPresence::~Win32DesktopPresence() {
  Destroy();
}

void Win32DesktopPresence::Attach(
    HWND hwnd,
    flutter::MethodChannel<flutter::EncodableValue>* channel) {
  hwnd_ = hwnd;
  channel_ = channel;
}

void Win32DesktopPresence::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = AsMap(call.arguments());
  if (call.method_name() == "setTray") {
    const bool visible = args ? MapBool(*args, "visible", false) : false;
    const std::wstring tooltip =
        Utf8ToWide(args ? MapString(*args, "tooltip") : std::string());
    SetTray(visible, tooltip);
    result->Success();
    return;
  }
  if (call.method_name() == "setBadgeCount") {
    SetBadgeCount(args ? MapInt(*args, "count", 0) : 0);
    result->Success();
    return;
  }
  if (call.method_name() == "destroy") {
    Destroy();
    result->Success();
    return;
  }
  result->NotImplemented();
}

bool Win32DesktopPresence::HandleMessage(HWND hwnd,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) {
  if (message == kTrayCallback) {
    // NOTIFYICON_VERSION_4 packs the event in LOWORD(lParam) and the icon
    // id in HIWORD. Pre-v4 notifications put the event in the full lParam
    // (HIWORD 0), so accept either shape.
    const UINT event = LOWORD(lparam);
    const UINT icon_id = HIWORD(lparam);
    if (icon_id != 0 && icon_id != kTrayIconId) {
      return false;
    }
    if (event == WM_LBUTTONUP || event == NIN_SELECT ||
        event == NIN_KEYSELECT) {
      ShowFromTray();
      return true;
    }
    if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      POINT cursor{};
      ::GetCursorPos(&cursor);
      HMENU menu = ::CreatePopupMenu();
      ::AppendMenuW(menu, MF_STRING, kTrayShowId, L"Show Alera");
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      ::AppendMenuW(menu, MF_STRING, kTrayQuitId, L"Quit");
      ::SetForegroundWindow(hwnd);
      const UINT command = ::TrackPopupMenu(
          menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, hwnd,
          nullptr);
      ::DestroyMenu(menu);
      if (command == kTrayShowId) {
        ShowFromTray();
      } else if (command == kTrayQuitId) {
        QuitFromTray();
      }
      return true;
    }
    return true;
  }
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    if (tray_visible_) {
      tray_visible_ = false;
      SetTray(true, nid_.szTip);
    }
    return true;
  }
  if (taskbar_button_created_message_ != 0 &&
      message == taskbar_button_created_message_) {
    UpdateOverlay();
    return true;
  }
  return false;
}

void Win32DesktopPresence::Destroy() {
  if (tray_visible_ && hwnd_) {
    ::Shell_NotifyIconW(NIM_DELETE, &nid_);
    tray_visible_ = false;
  }
  if (overlay_icon_) {
    ::DestroyIcon(overlay_icon_);
    overlay_icon_ = nullptr;
  }
  badge_count_ = 0;
  if (hwnd_) {
    ITaskbarList3* taskbar = nullptr;
    if (SUCCEEDED(::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(&taskbar)))) {
      taskbar->HrInit();
      taskbar->SetOverlayIcon(hwnd_, nullptr, L"");
      taskbar->Release();
    }
  }
}

void Win32DesktopPresence::SetTray(bool visible, const std::wstring& tooltip) {
  if (!hwnd_) {
    return;
  }
  if (!visible) {
    if (tray_visible_) {
      ::Shell_NotifyIconW(NIM_DELETE, &nid_);
      tray_visible_ = false;
    }
    return;
  }
  if (tray_icon_ == nullptr) {
    tray_icon_ = static_cast<HICON>(::LoadImageW(
        ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        0, 0, LR_DEFAULTSIZE | LR_SHARED));
  }
  ZeroMemory(&nid_, sizeof(nid_));
  nid_.cbSize = sizeof(nid_);
  nid_.hWnd = hwnd_;
  nid_.uID = kTrayIconId;
  nid_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  nid_.uCallbackMessage = kTrayCallback;
  nid_.hIcon = tray_icon_;
  wcsncpy_s(nid_.szTip, tooltip.c_str(), _TRUNCATE);
  if (tray_visible_) {
    ::Shell_NotifyIconW(NIM_MODIFY, &nid_);
    return;
  }
  if (::Shell_NotifyIconW(NIM_ADD, &nid_)) {
    nid_.uVersion = NOTIFYICON_VERSION_4;
    ::Shell_NotifyIconW(NIM_SETVERSION, &nid_);
    tray_visible_ = true;
  }
}

void Win32DesktopPresence::SetBadgeCount(int count) {
  badge_count_ = count < 0 ? 0 : count;
  UpdateOverlay();
}

void Win32DesktopPresence::ShowFromTray() {
  if (channel_) {
    channel_->InvokeMethod("trayShow", nullptr);
  }
}

void Win32DesktopPresence::QuitFromTray() {
  if (channel_) {
    channel_->InvokeMethod("trayQuit", nullptr);
  }
}

HICON Win32DesktopPresence::CreateBadgeIcon(int count) {
  const int size = ::GetSystemMetrics(SM_CXSMICON);
  const int dim = size > 0 ? size : 16;
  HDC screen = ::GetDC(nullptr);
  HDC dc = ::CreateCompatibleDC(screen);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = dim;
  info.bmiHeader.biHeight = -dim;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP color = ::CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  HGDIOBJ old = ::SelectObject(dc, color);
  RECT rect{0, 0, dim, dim};
  HBRUSH brush = ::CreateSolidBrush(RGB(0xC0, 0x28, 0x2C));
  ::FillRect(dc, &rect, brush);
  ::DeleteObject(brush);
  ::SetBkMode(dc, TRANSPARENT);
  ::SetTextColor(dc, RGB(255, 255, 255));
  const std::wstring label = BadgeLabel(count);
  LOGFONTW font{};
  font.lfHeight = -((dim * 3) / 4);
  font.lfWeight = FW_BOLD;
  font.lfQuality = ANTIALIASED_QUALITY;
  wcscpy_s(font.lfFaceName, L"Segoe UI");
  HFONT hfont = ::CreateFontIndirectW(&font);
  HGDIOBJ old_font = ::SelectObject(dc, hfont);
  ::DrawTextW(dc, label.c_str(), -1, &rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  ::SelectObject(dc, old_font);
  ::DeleteObject(hfont);
  if (bits != nullptr) {
    auto* pixels = static_cast<DWORD*>(bits);
    const int pixel_count = dim * dim;
    for (int i = 0; i < pixel_count; i += 1) {
      pixels[i] |= 0xFF000000;
    }
  }
  HBITMAP mask = ::CreateBitmap(dim, dim, 1, 1, nullptr);
  HDC mask_dc = ::CreateCompatibleDC(screen);
  HGDIOBJ old_mask = ::SelectObject(mask_dc, mask);
  ::PatBlt(mask_dc, 0, 0, dim, dim, BLACKNESS);
  ::SelectObject(mask_dc, old_mask);
  ::DeleteDC(mask_dc);
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmMask = mask;
  icon_info.hbmColor = color;
  HICON icon = ::CreateIconIndirect(&icon_info);
  ::SelectObject(dc, old);
  ::DeleteObject(color);
  ::DeleteObject(mask);
  ::DeleteDC(dc);
  ::ReleaseDC(nullptr, screen);
  return icon;
}

void Win32DesktopPresence::UpdateOverlay() {
  if (!hwnd_) {
    return;
  }
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar)))) {
    return;
  }
  taskbar->HrInit();
  if (overlay_icon_) {
    ::DestroyIcon(overlay_icon_);
    overlay_icon_ = nullptr;
  }
  if (badge_count_ > 0) {
    overlay_icon_ = CreateBadgeIcon(badge_count_);
    const std::wstring label = BadgeLabel(badge_count_);
    taskbar->SetOverlayIcon(hwnd_, overlay_icon_, label.c_str());
  } else {
    taskbar->SetOverlayIcon(hwnd_, nullptr, L"");
  }
  taskbar->Release();
}
