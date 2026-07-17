#include "win32_dark_mode.h"

#include <memory>
#include <vector>

namespace {

// Mirror of the AleraTokens palette in lib/src/app/theme/alera_tokens.dart
// (the app is dark-only, so there is no light variant to resolve).
constexpr COLORREF kMenuBarBackground = RGB(0x18, 0x18, 0x18);  // surface
constexpr COLORREF kMenuBarHighlight = RGB(0x24, 0x24, 0x24);   // surfaceElevated
constexpr COLORREF kMenuBarText = RGB(0xF5, 0xF5, 0xF5);        // foreground

// Undocumented uxtheme.dll ordinals, stable since Windows 10 1809 and used by
// inbox apps to render dark menus. They must be resolved dynamically so older
// builds degrade to light menus instead of failing to start.
enum class PreferredAppMode : int {
  kDefault = 0,
  kAllowDark = 1,
  kForceDark = 2,
  kForceLight = 3,
  kMax = 4,
};

using FnAllowDarkModeForWindow = BOOL(WINAPI*)(HWND, BOOL);  // ordinal 133
using FnAllowDarkModeForApp = BOOL(WINAPI*)(BOOL);           // ordinal 135 (1809)
using FnSetPreferredAppMode = PreferredAppMode(WINAPI*)(PreferredAppMode);  // ordinal 135 (1903+)
using FnFlushMenuThemes = void(WINAPI*)();                   // ordinal 136
using FnRefreshImmersiveColorPolicyState = void(WINAPI*)();  // ordinal 104
using FnRtlGetVersion = LONG(WINAPI*)(POSVERSIONINFOW);

HMODULE UxThemeModule() {
  static HMODULE uxtheme = ::LoadLibraryW(L"uxtheme.dll");
  return uxtheme;
}

HBRUSH MenuBarBackgroundBrush() {
  static HBRUSH brush = ::CreateSolidBrush(kMenuBarBackground);
  return brush;
}

HBRUSH MenuBarHighlightBrush() {
  static HBRUSH brush = ::CreateSolidBrush(kMenuBarHighlight);
  return brush;
}

// Stable backing storage for the strings referenced by owner-draw item data.
std::vector<std::unique_ptr<wchar_t[]>>& MenuBarTitles() {
  static std::vector<std::unique_ptr<wchar_t[]>> titles;
  return titles;
}

struct MenuFontCache {
  UINT dpi = 0;
  HFONT font = nullptr;
};

MenuFontCache& FontCache() {
  static MenuFontCache cache;
  return cache;
}

HFONT MenuFontForDpi(UINT dpi) {
  MenuFontCache& cache = FontCache();
  if (cache.font != nullptr && cache.dpi == dpi) {
    return cache.font;
  }
  if (cache.font != nullptr) {
    ::DeleteObject(cache.font);
    cache.font = nullptr;
  }
  NONCLIENTMETRICSW metrics{};
  metrics.cbSize = sizeof(metrics);
  if (::SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                                   &metrics, 0, dpi)) {
    cache.font = ::CreateFontIndirectW(&metrics.lfMenuFont);
    cache.dpi = dpi;
  }
  return cache.font;
}

void ConvertTopLevelItemsToOwnerDraw(HMENU menu_bar) {
  const int count = ::GetMenuItemCount(menu_bar);
  wchar_t title_buffer[128];
  for (int i = 0; i < count; ++i) {
    MENUITEMINFOW info{};
    info.cbSize = sizeof(info);
    info.fMask = MIIM_SUBMENU | MIIM_STRING;
    info.dwTypeData = title_buffer;
    info.cch = ARRAYSIZE(title_buffer);
    if (!::GetMenuItemInfoW(menu_bar, i, TRUE, &info) ||
        info.hSubMenu == nullptr) {
      continue;
    }
    auto title = std::make_unique<wchar_t[]>(::lstrlenW(title_buffer) + 1);
    ::lstrcpyW(title.get(), title_buffer);

    MENUITEMINFOW update{};
    update.cbSize = sizeof(update);
    update.fMask = MIIM_FTYPE | MIIM_DATA;
    update.fType = MFT_OWNERDRAW;
    update.dwItemData = reinterpret_cast<ULONG_PTR>(title.get());
    if (::SetMenuItemInfoW(menu_bar, i, TRUE, &update)) {
      MenuBarTitles().push_back(std::move(title));
    }
  }
}

}  // namespace

void EnableAleraDarkMode() {
  HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  HMODULE uxtheme = UxThemeModule();
  if (ntdll == nullptr || uxtheme == nullptr) {
    return;
  }
  auto rtl_get_version = reinterpret_cast<FnRtlGetVersion>(
      ::GetProcAddress(ntdll, "RtlGetVersion"));
  OSVERSIONINFOW os{};
  os.dwOSVersionInfoSize = sizeof(os);
  if (rtl_get_version == nullptr || rtl_get_version(&os) != 0 ||
      os.dwMajorVersion < 10) {
    return;
  }
  if (os.dwBuildNumber >= 18362) {  // Windows 10 1903+
    auto set_preferred_app_mode = reinterpret_cast<FnSetPreferredAppMode>(
        ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
    if (set_preferred_app_mode != nullptr) {
      set_preferred_app_mode(PreferredAppMode::kForceDark);
    }
  } else if (os.dwBuildNumber >= 17763) {  // Windows 10 1809
    auto allow_dark_mode_for_app = reinterpret_cast<FnAllowDarkModeForApp>(
        ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
    if (allow_dark_mode_for_app != nullptr) {
      allow_dark_mode_for_app(TRUE);
    }
  }
  if (auto refresh = reinterpret_cast<FnRefreshImmersiveColorPolicyState>(
          ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(104)))) {
    refresh();
  }
  if (auto flush_menu_themes = reinterpret_cast<FnFlushMenuThemes>(
          ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)))) {
    flush_menu_themes();
  }
}

void ApplyAleraDarkMenuBar(HWND hwnd, HMENU menu_bar) {
  if (HMODULE uxtheme = UxThemeModule()) {
    if (auto allow_dark_mode_for_window =
            reinterpret_cast<FnAllowDarkModeForWindow>(
                ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(133)))) {
      allow_dark_mode_for_window(hwnd, TRUE);
    }
  }

  MENUINFO menu_info{};
  menu_info.cbSize = sizeof(menu_info);
  menu_info.fMask = MIM_BACKGROUND;
  menu_info.hbrBack = MenuBarBackgroundBrush();
  ::SetMenuInfo(menu_bar, &menu_info);

  ConvertTopLevelItemsToOwnerDraw(menu_bar);
  ::DrawMenuBar(hwnd);
}

bool HandleAleraMenuBarMeasureItem(HWND hwnd, LPARAM lparam) {
  auto* measure = reinterpret_cast<MEASUREITEMSTRUCT*>(lparam);
  if (measure->CtlType != ODT_MENU || measure->itemData == 0) {
    return false;
  }
  const wchar_t* text = reinterpret_cast<const wchar_t*>(measure->itemData);
  const UINT dpi = ::GetDpiForWindow(hwnd);
  SIZE text_size{};
  if (HDC dc = ::GetDC(hwnd)) {
    HGDIOBJ old_font = nullptr;
    if (HFONT font = MenuFontForDpi(dpi)) {
      old_font = ::SelectObject(dc, font);
    }
    ::GetTextExtentPoint32W(dc, text, static_cast<int>(::lstrlenW(text)),
                            &text_size);
    if (old_font != nullptr) {
      ::SelectObject(dc, old_font);
    }
    ::ReleaseDC(hwnd, dc);
  }
  const int horizontal_padding = ::MulDiv(9, dpi, 96);
  const int vertical_padding = ::MulDiv(2, dpi, 96);
  measure->itemWidth = text_size.cx + horizontal_padding * 2;
  const UINT bar_height = ::GetSystemMetricsForDpi(SM_CYMENU, dpi);
  const UINT text_height = text_size.cy + vertical_padding * 2;
  measure->itemHeight =
      bar_height > text_height ? bar_height : text_height;
  return true;
}

bool HandleAleraMenuBarDrawItem(HWND hwnd, WPARAM wparam, LPARAM lparam) {
  if (wparam != 0) {
    return false;  // Not a menu item.
  }
  auto* draw = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
  if (draw->CtlType != ODT_MENU || draw->itemData == 0) {
    return false;
  }
  const wchar_t* text = reinterpret_cast<const wchar_t*>(draw->itemData);
  const bool highlighted =
      (draw->itemState & (ODS_SELECTED | ODS_HOTLIGHT)) != 0;
  ::FillRect(draw->hDC, &draw->rcItem,
             highlighted ? MenuBarHighlightBrush() : MenuBarBackgroundBrush());

  HGDIOBJ old_font = nullptr;
  if (HFONT font = MenuFontForDpi(::GetDpiForWindow(hwnd))) {
    old_font = ::SelectObject(draw->hDC, font);
  }
  ::SetBkMode(draw->hDC, TRANSPARENT);
  ::SetTextColor(draw->hDC, kMenuBarText);
  ::DrawTextW(draw->hDC, text, -1, &draw->rcItem,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  if (old_font != nullptr) {
    ::SelectObject(draw->hDC, old_font);
  }
  return true;
}

void RefreshAleraMenuBarForDpi(HWND hwnd) {
  MenuFontCache& cache = FontCache();
  if (cache.font != nullptr) {
    ::DeleteObject(cache.font);
    cache.font = nullptr;
    cache.dpi = 0;
  }
  ::DrawMenuBar(hwnd);
}
