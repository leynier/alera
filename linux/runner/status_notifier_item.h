#ifndef FLUTTER_STATUS_NOTIFIER_ITEM_H_
#define FLUTTER_STATUS_NOTIFIER_ITEM_H_

#include <gio/gio.h>

typedef struct _StatusNotifierItem StatusNotifierItem;

typedef struct {
  void (*on_activate)(gpointer user_data);
  void (*on_quit)(gpointer user_data);
} StatusNotifierItemCallbacks;

// TRUE when some panel owns org.kde.StatusNotifierWatcher, which is the only
// case where our own item is worth publishing.
gboolean status_notifier_item_host_available();

// Publishes a StatusNotifierItem owned by this process. Unlike
// libayatana-appindicator it answers Activate and carries IconPixmap, which is
// what lets the tray icon show a badge.
StatusNotifierItem* status_notifier_item_new(
    const gchar* title,
    StatusNotifierItemCallbacks callbacks,
    gpointer user_data);

void status_notifier_item_set_active(StatusNotifierItem* item, gboolean active);

void status_notifier_item_set_tooltip(StatusNotifierItem* item,
                                      const gchar* tooltip);

void status_notifier_item_set_badge_count(StatusNotifierItem* item, int count);

void status_notifier_item_free(StatusNotifierItem* item);

#endif  // FLUTTER_STATUS_NOTIFIER_ITEM_H_
