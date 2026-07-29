#ifndef ALERA_BROWSER_LINUX_BROWSER_OVERLAY_ALLOCATION_H_
#define ALERA_BROWSER_LINUX_BROWSER_OVERLAY_ALLOCATION_H_

// Pure frame math for GtkOverlay get-child-position. Kept free of GTK so the
// linux unit tests can exercise the gate without linking the full plugin.
struct BrowserOverlayAllocation {
  int x;
  int y;
  int width;
  int height;
};

// Fills [allocation] with the exact Flutter-reported frame for a browser page
// overlay child. Returns true only when width and height are positive so
// GtkOverlay keeps its default layout for invalid or unmeasured pages.
inline bool browser_page_fill_overlay_allocation(
    int frame_x,
    int frame_y,
    int frame_width,
    int frame_height,
    BrowserOverlayAllocation* allocation) {
  if (allocation == nullptr || frame_width <= 0 || frame_height <= 0) {
    return false;
  }
  allocation->x = frame_x;
  allocation->y = frame_y;
  allocation->width = frame_width;
  allocation->height = frame_height;
  return true;
}

#endif
