#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "win32_dark_mode.h"
#include "win32_single_instance.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  Win32SingleInstance single_instance(ALERA_APP_ID);
  const auto start = single_instance.Start();
  if (start == Win32SingleInstance::StartResult::forwarded) {
    return EXIT_SUCCESS;
  }
  if (start == Win32SingleInstance::StartResult::failed) {
    ::MessageBoxW(nullptr, L"Unable to activate the Alera application instance.",
                  ALERA_APP_NAME, MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  // Alera is dark-only; must run before any menu or window is created so the
  // OS renders dark popup menus for the whole process.
  EnableAleraDarkMode();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_initialized = SUCCEEDED(com_result);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(ALERA_APP_NAME, origin, size)) {
    // Create() can initialize the Flutter controller before reporting a
    // failure. Tear it down while COM is still available, then balance the
    // successful apartment initialization before returning.
    window.Destroy();
    if (com_initialized) {
      ::CoUninitialize();
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  const int exit_code = single_instance.RunMessageLoop(window.GetHandle());

  // window_manager's destroy() only posts WM_QUIT, so the HWND outlives the
  // loop. Tear the Flutter view down through OnDestroy while COM is still
  // initialized; destroying it as a member later dispatches messages to a
  // controller that is being freed.
  window.Destroy();
  if (com_initialized) {
    ::CoUninitialize();
  }
  return exit_code;
}
