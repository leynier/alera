#ifndef ALERA_BROWSER_LINUX_BROWSER_NAVIGATION_STATE_H_
#define ALERA_BROWSER_LINUX_BROWSER_NAVIGATION_STATE_H_

struct LinuxBrowserNavigationState {
  bool failed;
};

inline void linux_browser_navigation_started(
    LinuxBrowserNavigationState* state) {
  state->failed = false;
}

inline void linux_browser_navigation_failed(
    LinuxBrowserNavigationState* state) {
  state->failed = true;
}

inline bool linux_browser_navigation_should_finish(
    const LinuxBrowserNavigationState* state) {
  return !state->failed;
}

#endif
