#include "../browser_overlay_allocation.h"

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
  bool succeeded = true;
  BrowserOverlayAllocation allocation{};

  succeeded &= Expect(
      browser_page_fill_overlay_allocation(12, 34, 640, 480, &allocation),
      "a valid frame should fill the overlay allocation");
  succeeded &= Expect(allocation.x == 12, "frame x was not applied");
  succeeded &= Expect(allocation.y == 34, "frame y was not applied");
  succeeded &= Expect(allocation.width == 640, "frame width was not applied");
  succeeded &=
      Expect(allocation.height == 480, "frame height was not applied");

  succeeded &= Expect(
      !browser_page_fill_overlay_allocation(0, 0, 0, 100, &allocation),
      "zero width should not claim overlay allocation");
  succeeded &= Expect(
      !browser_page_fill_overlay_allocation(0, 0, 100, 0, &allocation),
      "zero height should not claim overlay allocation");
  succeeded &= Expect(
      !browser_page_fill_overlay_allocation(0, 0, -1, 100, &allocation),
      "negative width should not claim overlay allocation");
  succeeded &= Expect(
      !browser_page_fill_overlay_allocation(0, 0, 100, 100, nullptr),
      "a null allocation pointer should not claim overlay allocation");

  return succeeded ? 0 : 1;
}
