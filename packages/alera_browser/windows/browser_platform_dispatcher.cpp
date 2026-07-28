#include "browser_platform_dispatcher.h"

#include <algorithm>
#include <utility>

namespace alera_browser {

BrowserPlatformDispatcher::BrowserPlatformDispatcher(HWND view_window)
    : target_window_(
          view_window == nullptr
              ? nullptr
              : GetAncestor(view_window, GA_ROOT)) {}

bool BrowserPlatformDispatcher::Post(Task task) {
  auto queued = std::make_shared<Task>(std::move(task));
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) {
      return false;
    }
    tasks_.push_back(queued);
  }
  if (target_window_ != nullptr &&
      PostMessageW(target_window_, kMessage, 0, 0)) {
    return true;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  const auto iterator =
      std::find(tasks_.begin(), tasks_.end(), queued);
  if (iterator != tasks_.end()) {
    tasks_.erase(iterator);
  }
  return false;
}

void BrowserPlatformDispatcher::Drain() {
  std::deque<std::shared_ptr<Task>> tasks;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) {
      return;
    }
    tasks.swap(tasks_);
  }
  for (const auto& task : tasks) {
    (*task)();
  }
}

void BrowserPlatformDispatcher::Close() {
  std::lock_guard<std::mutex> lock(mutex_);
  closed_ = true;
  tasks_.clear();
}

}  // namespace alera_browser
