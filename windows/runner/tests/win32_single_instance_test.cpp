#include "win32_single_instance.h"

#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr DWORD kPrimary = 10;
constexpr DWORD kForwarded = 11;
constexpr DWORD kFailed = 12;
constexpr UINT_PTR kCheckWindow = 1;
constexpr UINT_PTR kLaunchAgain = 2;

bool Expect(bool condition, const char* description) {
  std::cout << (condition ? "PASS: " : "FAIL: ") << description << '\n';
  return condition;
}

std::wstring TestId(const wchar_t* suffix) {
  return L"dev.leynier.alera.test." + std::to_wstring(::GetCurrentProcessId()) +
         L"." + suffix;
}

class ChildProcess {
 public:
  ChildProcess(const std::wstring& mode, const std::wstring& id) {
    wchar_t executable[32768]{};
    ::GetModuleFileNameW(nullptr, executable, 32768);
    std::wstring command =
        L"\"" + std::wstring(executable) + L"\" " + mode + L" \"" + id + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    ::CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process_);
  }

  ~ChildProcess() {
    if (process_.hProcess) {
      if (::WaitForSingleObject(process_.hProcess, 0) == WAIT_TIMEOUT) {
        ::TerminateProcess(process_.hProcess, kFailed);
        ::WaitForSingleObject(process_.hProcess, 5000);
      }
      ::CloseHandle(process_.hProcess);
      ::CloseHandle(process_.hThread);
    }
  }

  DWORD Wait(DWORD timeout = 5000) const {
    if (!process_.hProcess ||
        ::WaitForSingleObject(process_.hProcess, timeout) != WAIT_OBJECT_0) {
      return STILL_ACTIVE;
    }
    DWORD code = kFailed;
    ::GetExitCodeProcess(process_.hProcess, &code);
    return code;
  }

 private:
  PROCESS_INFORMATION process_{};
};

bool ChecksOwnershipAndFlavors() {
  const auto id = TestId(L"ownership");
  {
    Win32SingleInstance instance(id);
    if (!Expect(instance.Start() == Win32SingleInstance::StartResult::primary,
                "first launch owns the instance")) {
      return false;
    }
    if (!Expect(ChildProcess(L"--probe", id).Wait() == kForwarded,
                "second process forwards before any window exists") ||
        !Expect(ChildProcess(L"--probe", id + L".dev").Wait() == kPrimary,
                "dev and release identities can coexist")) {
      return false;
    }
  }
  return Expect(ChildProcess(L"--probe", id).Wait() == kPrimary,
                "quitting releases ownership for a fresh launch");
}

bool ChecksConcurrentLaunches() {
  const auto id = TestId(L"concurrent");
  HANDLE release = ::CreateEventW(nullptr, TRUE, FALSE,
                                  (L"Local\\" + id + L".release").c_str());
  std::vector<std::unique_ptr<ChildProcess>> children;
  for (int i = 0; i < 8; ++i) {
    children.push_back(std::make_unique<ChildProcess>(L"--compete", id));
  }
  int forwarded = 0;
  const ULONGLONG deadline = ::GetTickCount64() + 5000;
  do {
    forwarded = 0;
    for (const auto& child : children) {
      if (child->Wait(0) == kForwarded) {
        ++forwarded;
      }
    }
    if (forwarded == 7) {
      break;
    }
    ::Sleep(10);
  } while (::GetTickCount64() < deadline);
  ::SetEvent(release);
  int primary = 0;
  for (const auto& child : children) {
    if (child->Wait() == kPrimary) {
      ++primary;
    }
  }
  ::CloseHandle(release);
  return Expect(primary == 1 && forwarded == 7,
                "eight concurrent cold launches create exactly one owner");
}

bool ChecksAbandonedOwnership() {
  const auto id = TestId(L"abandoned");
  // Keep the kernel object alive so the next launch sees WAIT_ABANDONED,
  // rather than merely creating a new mutex after the crashed process exits.
  HANDLE mutex = ::CreateMutexW(nullptr, FALSE,
                                (L"Local\\" + id + L".desktop.mutex").c_str());
  const DWORD crashed = ChildProcess(L"--crash", id).Wait();
  Win32SingleInstance instance(id);
  const auto start = instance.Start();
  ::CloseHandle(mutex);
  return Expect(
      crashed == kPrimary && start == Win32SingleInstance::StartResult::primary,
      "a crashed owner does not block the next launch");
}

struct WindowCheck {
  std::wstring id;
  bool maximized = false;
  bool passed = false;
  bool forwarded = true;
};

LRESULT CALLBACK TestWindowProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  if (message == WM_TIMER) {
    auto* check = reinterpret_cast<WindowCheck*>(
        ::GetWindowLongPtrW(window, GWLP_USERDATA));
    if (wparam == kLaunchAgain) {
      ::KillTimer(window, kLaunchAgain);
      check->forwarded =
          ChildProcess(L"--probe", check->id).Wait() == kForwarded;
      ::SetTimer(window, kCheckWindow, 150, nullptr);
      return 0;
    }
    check->passed = ::IsWindowVisible(window) && !::IsIconic(window) &&
                    (::IsZoomed(window) != FALSE) == check->maximized;
    ::KillTimer(window, kCheckWindow);
    ::PostQuitMessage(check->passed ? 0 : 1);
    return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

bool ChecksWindowActivation(int show_state, bool hide, bool before_window,
                            const wchar_t* suffix) {
  const auto id = TestId(suffix);
  Win32SingleInstance instance(id);
  if (instance.Start() != Win32SingleInstance::StartResult::primary) {
    return false;
  }
  if (before_window && ChildProcess(L"--probe", id).Wait() != kForwarded) {
    return false;
  }

  WindowCheck check;
  check.id = id;
  check.maximized = show_state == SW_SHOWMAXIMIZED;
  HWND window = ::CreateWindowW(L"AleraSingleInstanceTest",
                                L"An unrelated mutable window title",
                                WS_OVERLAPPEDWINDOW, 0, 0, 320, 200, nullptr,
                                nullptr, ::GetModuleHandleW(nullptr), &check);
  if (!window) {
    return false;
  }
  if (show_state != SW_HIDE) {
    ::ShowWindow(window, show_state);
  }
  if (hide) {
    ::ShowWindow(window, SW_HIDE);
  }
  ::SetTimer(window, before_window ? kCheckWindow : kLaunchAgain, 150, nullptr);
  const int result = instance.RunMessageLoop(window);
  ::DestroyWindow(window);
  return result == 0 && check.passed && check.forwarded;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc == 3) {
    const std::wstring mode = argv[1];
    Win32SingleInstance instance(argv[2]);
    const auto start = instance.Start();
    if (start == Win32SingleInstance::StartResult::primary) {
      if (mode == L"--crash") {
        ::ExitProcess(kPrimary);
      }
      if (mode == L"--compete") {
        HANDLE release = ::OpenEventW(
            SYNCHRONIZE, FALSE,
            (L"Local\\" + std::wstring(argv[2]) + L".release").c_str());
        ::WaitForSingleObject(release, 10000);
        ::CloseHandle(release);
      }
      return kPrimary;
    }
    return start == Win32SingleInstance::StartResult::forwarded ? kForwarded
                                                                : kFailed;
  }

  WNDCLASSW window_class{};
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.lpszClassName = L"AleraSingleInstanceTest";
  window_class.lpfnWndProc = TestWindowProc;
  ::RegisterClassW(&window_class);

  bool passed = ChecksOwnershipAndFlavors();
  passed = ChecksConcurrentLaunches() && passed;
  passed = ChecksAbandonedOwnership() && passed;
  passed = Expect(ChecksWindowActivation(SW_HIDE, true, true, L"early"),
                  "activation survives a launch before window creation") &&
           passed;
  passed = Expect(ChecksWindowActivation(SW_HIDE, true, false, L"hidden"),
                  "a hidden window is shown again") &&
           passed;
  passed =
      Expect(ChecksWindowActivation(SW_MINIMIZE, false, false, L"minimized"),
             "a minimized window is restored") &&
      passed;
  passed = Expect(ChecksWindowActivation(SW_SHOWMAXIMIZED, true, false,
                                         L"maximized"),
                  "a hidden maximized window keeps its maximized state") &&
           passed;
  passed = Expect(ChecksWindowActivation(SW_SHOW, false, false, L"visible"),
                  "an already visible window remains visible") &&
           passed;
  Win32SingleInstance invalid(L"invalid\\object\\name");
  passed = Expect(invalid.Start() == Win32SingleInstance::StartResult::failed,
                  "synchronization errors do not permit duplicate startup") &&
           passed;
  ::UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
  return passed ? 0 : 1;
}
