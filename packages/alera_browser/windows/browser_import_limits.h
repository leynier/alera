#ifndef ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_LIMITS_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_IMPORT_LIMITS_H_

#include <cstddef>

namespace alera_browser {

inline constexpr size_t kManualCookieJsonMaximumBytes =
    16 * 1024 * 1024;
inline constexpr size_t kManualCookieMaximumCount = 100000;

constexpr bool ManualCookieJsonWithinLimit(size_t byte_length) {
  return byte_length <= kManualCookieJsonMaximumBytes;
}

}  // namespace alera_browser

#endif
