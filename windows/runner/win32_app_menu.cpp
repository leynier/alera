#include "win32_app_menu.h"

HMENU CreateWin32AppMenu() {
  HMENU menu_bar = ::CreateMenu();
  if (menu_bar == nullptr) {
    return nullptr;
  }

  HMENU app_menu = ::CreatePopupMenu();
  if (app_menu == nullptr) {
    ::DestroyMenu(menu_bar);
    return nullptr;
  }
  ::AppendMenuW(app_menu, MF_STRING, kWin32AppMenuOpenSettings,
                L"Settings ...");
  ::AppendMenuW(app_menu, MF_STRING, kWin32AppMenuCheckForUpdates,
                L"Check for Updates ...");
  ::AppendMenuW(app_menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(app_menu, MF_STRING, kWin32AppMenuShowAbout,
                L"About " ALERA_APP_NAME);
  ::AppendMenuW(app_menu, MF_STRING, kWin32AppMenuExitApp, L"Exit");
  ::AppendMenuW(menu_bar, MF_POPUP, reinterpret_cast<UINT_PTR>(app_menu),
                ALERA_APP_NAME);

  HMENU edit_menu = ::CreatePopupMenu();
  if (edit_menu == nullptr) {
    ::DestroyMenu(menu_bar);
    return nullptr;
  }
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuUndo, L"Undo");
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuRedo, L"Redo");
  ::AppendMenuW(edit_menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuCut, L"Cut");
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuCopy, L"Copy");
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuPaste, L"Paste");
  ::AppendMenuW(edit_menu, MF_STRING, kWin32AppMenuSelectAll, L"Select All");
  ::AppendMenuW(menu_bar, MF_POPUP, reinterpret_cast<UINT_PTR>(edit_menu),
                L"Edit");

  return menu_bar;
}

const char* Win32AppMenuMethodForCommand(UINT command_id) {
  switch (command_id) {
    case kWin32AppMenuOpenSettings:
      return "openSettings";
    case kWin32AppMenuCheckForUpdates:
      return "checkForUpdates";
    case kWin32AppMenuShowAbout:
      return "showAbout";
    case kWin32AppMenuExitApp:
      return "exitApp";
    case kWin32AppMenuUndo:
      return "undo";
    case kWin32AppMenuRedo:
      return "redo";
    case kWin32AppMenuCut:
      return "cut";
    case kWin32AppMenuCopy:
      return "copy";
    case kWin32AppMenuPaste:
      return "paste";
    case kWin32AppMenuSelectAll:
      return "selectAll";
    default:
      return nullptr;
  }
}
