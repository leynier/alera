#ifndef FLUTTER_STATUS_NOTIFIER_MENU_H_
#define FLUTTER_STATUS_NOTIFIER_MENU_H_

#include <gio/gio.h>

typedef struct _StatusNotifierMenu StatusNotifierMenu;

typedef void (*StatusNotifierMenuCallback)(gpointer user_data);

// Exports the two-entry tray menu over com.canonical.dbusmenu, which is how an
// SNI host renders a menu it cannot draw from our process. Returns nullptr when
// the object cannot be registered.
StatusNotifierMenu* status_notifier_menu_new(
    GDBusConnection* bus,
    const gchar* object_path,
    const gchar* show_label,
    StatusNotifierMenuCallback on_show,
    StatusNotifierMenuCallback on_quit,
    gpointer user_data);

void status_notifier_menu_free(StatusNotifierMenu* menu);

#endif  // FLUTTER_STATUS_NOTIFIER_MENU_H_
