#include "../browser_navigation_state.h"

#include <iostream>

namespace {

bool Expect(bool value, const char* message) {
  if (!value) {
    std::cerr << message << '\n';
  }
  return value;
}

}  // namespace

int main() {
  LinuxBrowserNavigationState state{};
  bool succeeded = true;
  succeeded &= Expect(
      linux_browser_navigation_should_finish(&state),
      "a fresh navigation could not finish");

  linux_browser_navigation_failed(&state);
  succeeded &= Expect(
      !linux_browser_navigation_should_finish(&state),
      "an ordinary failure still allowed navigationFinished");

  linux_browser_navigation_started(&state);
  succeeded &= Expect(
      linux_browser_navigation_should_finish(&state),
      "a new navigation did not clear the previous failure");

  linux_browser_navigation_failed(&state);
  succeeded &= Expect(
      !linux_browser_navigation_should_finish(&state),
      "a TLS failure still allowed navigationFinished");
  return succeeded ? 0 : 1;
}
