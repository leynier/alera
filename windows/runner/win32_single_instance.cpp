#include "win32_single_instance.h"

#include <cstdlib>

Win32SingleInstance::Win32SingleInstance(const std::wstring& app_id)
    : object_name_(L"Local\\" + app_id + L".desktop"),
      window_property_(app_id + L".desktop.window") {}

Win32SingleInstance::~Win32SingleInstance() {
  if (owns_mutex_) {
    ::ReleaseMutex(mutex_);
  }
  if (mutex_) {
    ::CloseHandle(mutex_);
  }
  if (activation_event_) {
    ::CloseHandle(activation_event_);
  }
}

Win32SingleInstance::StartResult Win32SingleInstance::Start() {
  // Every contender opens the event before competing for the mutex. A second
  // launch can then queue activation even before the first creates its window.
  activation_event_ = ::CreateEventW(nullptr, FALSE, FALSE,
                                     (object_name_ + L".activate").c_str());
  mutex_ = ::CreateMutexW(nullptr, FALSE, (object_name_ + L".mutex").c_str());
  if (!activation_event_ || !mutex_) {
    return StartResult::failed;
  }

  const DWORD wait = ::WaitForSingleObject(mutex_, 0);
  if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
    owns_mutex_ = true;
    return StartResult::primary;
  }
  if (wait != WAIT_TIMEOUT) {
    return StartResult::failed;
  }

  // Windows gives the freshly launched process foreground rights. Pass those
  // rights to the existing window without relying on its mutable title.
  ::EnumWindows(AllowForegroundForWindow, reinterpret_cast<LPARAM>(this));
  return ::SetEvent(activation_event_) ? StartResult::forwarded
                                       : StartResult::failed;
}

BOOL CALLBACK Win32SingleInstance::AllowForegroundForWindow(HWND window,
                                                            LPARAM context) {
  const auto* instance = reinterpret_cast<Win32SingleInstance*>(context);
  if (!::GetPropW(window, instance->window_property_.c_str())) {
    return TRUE;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  ::AllowSetForegroundWindow(pid);
  return FALSE;
}

int Win32SingleInstance::RunMessageLoop(HWND window) {
  if (!owns_mutex_ || !::SetPropW(window, window_property_.c_str(),
                                  reinterpret_cast<HANDLE>(1))) {
    return EXIT_FAILURE;
  }

  int exit_code = EXIT_SUCCESS;
  bool running = true;
  while (running) {
    // INPUTAVAILABLE also wakes for messages Flutter has already inspected.
    // The event keeps idle instances asleep and retains early launch requests.
    const DWORD wait = ::MsgWaitForMultipleObjectsEx(
        1, &activation_event_, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    if (wait == WAIT_FAILED) {
      exit_code = EXIT_FAILURE;
      break;
    }
    if (wait == WAIT_OBJECT_0) {
      ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(window);
    }

    MSG message{};
    while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        exit_code = static_cast<int>(message.wParam);
        running = false;
        break;
      }
      ::TranslateMessage(&message);
      ::DispatchMessageW(&message);
    }
  }
  ::RemovePropW(window, window_property_.c_str());
  return exit_code;
}
