#ifndef FLUTTER_TRAY_BADGE_ICON_H_
#define FLUTTER_TRAY_BADGE_ICON_H_

#include <gdk-pixbuf/gdk-pixbuf.h>

// Renders the tray icon at |size| pixels with |count| drawn as a badge.
// A count of zero or less renders the plain icon. Returns nullptr when no base
// icon can be found, which is the caller's cue to fall back to an icon name.
GdkPixbuf* tray_badge_icon_render(int size, int count);

#endif  // FLUTTER_TRAY_BADGE_ICON_H_
