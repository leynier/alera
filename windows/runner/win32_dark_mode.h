#ifndef RUNNER_WIN32_DARK_MODE_H_
#define RUNNER_WIN32_DARK_MODE_H_

#include <windows.h>

// Enables dark mode for the whole process. Alera is dark-only, so this is
// applied unconditionally instead of following the OS theme. Uses undocumented
// but stable uxtheme ordinals; on unsupported builds the call is a no-op and
// menus keep the default light rendering.
void EnableAleraDarkMode();

// Applies dark rendering to the given menu bar: dark background brush and
// owner-drawn top-level items. The bar strip lives in the non-client area and
// does not follow the process dark mode; popup menus do, so they are left
// fully native.
void ApplyAleraDarkMenuBar(HWND hwnd, HMENU menu_bar);

// WM_MEASUREITEM / WM_DRAWITEM handlers for the owner-drawn top-level menu bar
// items. Return true when the message belonged to the menu bar.
bool HandleAleraMenuBarMeasureItem(HWND hwnd, LPARAM lparam);
bool HandleAleraMenuBarDrawItem(HWND hwnd, WPARAM wparam, LPARAM lparam);

// Drops the cached menu font and repaints the bar after a DPI change.
void RefreshAleraMenuBarForDpi(HWND hwnd);

#endif  // RUNNER_WIN32_DARK_MODE_H_
