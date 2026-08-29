#ifndef FLUTTER_APPINDICATOR_TRAY_FALLBACK_H_
#define FLUTTER_APPINDICATOR_TRAY_FALLBACK_H_

#include <gio/gio.h>

typedef struct _AppIndicatorTrayFallback AppIndicatorTrayFallback;

typedef void (*AppIndicatorTrayCallback)(gpointer user_data);

// Tray of last resort, for a desktop with no StatusNotifierWatcher, where
// libayatana-appindicator falls back to a GtkStatusIcon of its own. It cannot
// show a badge: the library exports neither IconPixmap nor a label KDE reads.
AppIndicatorTrayFallback* appindicator_tray_fallback_new(
    const gchar* show_label,
    AppIndicatorTrayCallback on_show,
    AppIndicatorTrayCallback on_quit,
    gpointer user_data);

void appindicator_tray_fallback_set_active(AppIndicatorTrayFallback* tray,
                                           gboolean active);

void appindicator_tray_fallback_free(AppIndicatorTrayFallback* tray);

#endif  // FLUTTER_APPINDICATOR_TRAY_FALLBACK_H_
