#ifndef RUNNER_WIN32_APP_MENU_H_
#define RUNNER_WIN32_APP_MENU_H_

#include <windows.h>

// Command ids for the native application menu.
enum Win32AppMenuCommandId : UINT {
  kWin32AppMenuOpenSettings = 1001,
  kWin32AppMenuCheckForUpdates,
  kWin32AppMenuShowAbout,
  kWin32AppMenuExitApp,
  kWin32AppMenuUndo,
  kWin32AppMenuRedo,
  kWin32AppMenuCut,
  kWin32AppMenuCopy,
  kWin32AppMenuPaste,
  kWin32AppMenuSelectAll,
};

// Builds the native application menu bar. Returns nullptr on failure.
// No keyboard accelerators are registered: global accelerators would swallow
// keys like Ctrl+C before text fields and the terminal-first shortcut policy
// see them.
HMENU CreateWin32AppMenu();

// Maps a WM_COMMAND id to the app-menu channel method, or nullptr when the
// command does not belong to the app menu. Method names stay in sync with
// lib/src/features/app_menu/infra/native_app_menu_channel.dart.
const char* Win32AppMenuMethodForCommand(UINT command_id);

#endif  // RUNNER_WIN32_APP_MENU_H_
