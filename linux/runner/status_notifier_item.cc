#include "status_notifier_item.h"

#include <unistd.h>

#include "status_notifier_menu.h"
#include "tray_badge_icon.h"

namespace {

constexpr char kWatcherName[] = "org.kde.StatusNotifierWatcher";
constexpr char kWatcherPath[] = "/StatusNotifierWatcher";
constexpr char kItemInterface[] = "org.kde.StatusNotifierItem";
constexpr char kItemPath[] = "/StatusNotifierItem";
constexpr char kMenuPath[] = "/StatusNotifierItem/Menu";
constexpr char kIconName[] = "alera";

// The host picks the closest one, so publishing a single size leaves it
// scaling a bitmap it did not have to.
constexpr int kIconSizes[] = {22, 24, 32, 48, 64};

constexpr char kInterfaceXml[] =
    "<node>"
    "  <interface name='org.kde.StatusNotifierItem'>"
    "    <property name='Category' type='s' access='read'/>"
    "    <property name='Id' type='s' access='read'/>"
    "    <property name='Title' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='WindowId' type='i' access='read'/>"
    "    <property name='IconName' type='s' access='read'/>"
    "    <property name='IconThemePath' type='s' access='read'/>"
    "    <property name='IconPixmap' type='a(iiay)' access='read'/>"
    "    <property name='OverlayIconName' type='s' access='read'/>"
    "    <property name='AttentionIconName' type='s' access='read'/>"
    "    <property name='ToolTip' type='(sa(iiay)ss)' access='read'/>"
    "    <property name='ItemIsMenu' type='b' access='read'/>"
    "    <property name='Menu' type='o' access='read'/>"
    "    <method name='Activate'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='SecondaryActivate'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='ContextMenu'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='Scroll'>"
    "      <arg type='i' name='delta' direction='in'/>"
    "      <arg type='s' name='orientation' direction='in'/>"
    "    </method>"
    "    <signal name='NewIcon'/>"
    "    <signal name='NewToolTip'/>"
    "    <signal name='NewTitle'/>"
    "    <signal name='NewStatus'>"
    "      <arg type='s' name='status'/>"
    "    </signal>"
    "  </interface>"
    "</node>";

}  // namespace

struct _StatusNotifierItem {
  GDBusConnection* bus;
  gchar* bus_name;
  gchar* title;
  gchar* tooltip;
  guint owner_id;
  guint registration;
  guint watcher_watch;
  gboolean name_acquired;
  gboolean active;
  int badge_count;
  GVariant* icon_pixmap;
  StatusNotifierMenu* menu;
  StatusNotifierItemCallbacks callbacks;
  gpointer user_data;
};

static void emit_signal(StatusNotifierItem* self,
                        const gchar* name,
                        GVariant* parameters) {
  if (self->bus == nullptr) {
    return;
  }
  g_dbus_connection_emit_signal(self->bus, nullptr, kItemPath, kItemInterface,
                                name, parameters, nullptr);
}

// The wire format is ARGB32 in network byte order and NOT premultiplied, which
// is why the pixels come from a GdkPixbuf rather than straight off a cairo
// surface.
static GVariant* pixbuf_to_argb32(GdkPixbuf* pixbuf) {
  const int width = gdk_pixbuf_get_width(pixbuf);
  const int height = gdk_pixbuf_get_height(pixbuf);
  const int stride = gdk_pixbuf_get_rowstride(pixbuf);
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const guchar* pixels = gdk_pixbuf_read_pixels(pixbuf);
  const gsize length = static_cast<gsize>(width) * height * 4;
  auto* argb = static_cast<guchar*>(g_malloc(length));
  gsize offset = 0;
  for (int y = 0; y < height; y += 1) {
    const guchar* row = pixels + static_cast<gsize>(y) * stride;
    for (int x = 0; x < width; x += 1) {
      const guchar* pixel = row + static_cast<gsize>(x) * channels;
      argb[offset + 0] = channels == 4 ? pixel[3] : 0xFF;
      argb[offset + 1] = pixel[0];
      argb[offset + 2] = pixel[1];
      argb[offset + 3] = pixel[2];
      offset += 4;
    }
  }
  return g_variant_new(
      "(ii@ay)", width, height,
      g_variant_new_from_data(G_VARIANT_TYPE("ay"), argb, length, TRUE, g_free,
                              argb));
}

static GVariant* build_icon_pixmap(StatusNotifierItem* self) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a(iiay)"));
  for (gsize i = 0; i < G_N_ELEMENTS(kIconSizes); i += 1) {
    GdkPixbuf* pixbuf = tray_badge_icon_render(kIconSizes[i], self->badge_count);
    if (pixbuf == nullptr) {
      continue;
    }
    g_variant_builder_add_value(&builder, pixbuf_to_argb32(pixbuf));
    g_object_unref(pixbuf);
  }
  return g_variant_ref_sink(g_variant_builder_end(&builder));
}

static GVariant* icon_pixmap(StatusNotifierItem* self) {
  if (self->icon_pixmap == nullptr) {
    self->icon_pixmap = build_icon_pixmap(self);
  }
  return self->icon_pixmap;
}

static GVariant* build_tooltip(StatusNotifierItem* self) {
  GVariantBuilder pixmaps;
  g_variant_builder_init(&pixmaps, G_VARIANT_TYPE("a(iiay)"));
  return g_variant_new("(sa(iiay)ss)", "", &pixmaps,
                       self->tooltip != nullptr ? self->tooltip : self->title,
                       "");
}

static GVariant* get_property_cb(GDBusConnection*,
                                 const gchar*,
                                 const gchar*,
                                 const gchar*,
                                 const gchar* property,
                                 GError**,
                                 gpointer user_data) {
  auto* self = static_cast<StatusNotifierItem*>(user_data);
  if (g_strcmp0(property, "Category") == 0) {
    return g_variant_new_string("ApplicationStatus");
  }
  if (g_strcmp0(property, "Id") == 0) {
    return g_variant_new_string(APPLICATION_ID);
  }
  if (g_strcmp0(property, "Title") == 0) {
    return g_variant_new_string(self->title);
  }
  if (g_strcmp0(property, "Status") == 0) {
    return g_variant_new_string(self->active ? "Active" : "Passive");
  }
  if (g_strcmp0(property, "WindowId") == 0) {
    return g_variant_new_int32(0);
  }
  if (g_strcmp0(property, "IconName") == 0) {
    // A host prefers IconName over IconPixmap when both are set, so the name
    // has to stay empty while we have pixmaps or the badge would never show.
    // It is the fallback for the case where no base icon could be loaded.
    const gboolean have_pixmaps = g_variant_n_children(icon_pixmap(self)) > 0;
    return g_variant_new_string(have_pixmaps ? "" : kIconName);
  }
  if (g_strcmp0(property, "IconPixmap") == 0) {
    return g_variant_ref(icon_pixmap(self));
  }
  if (g_strcmp0(property, "IconThemePath") == 0 ||
      g_strcmp0(property, "OverlayIconName") == 0 ||
      g_strcmp0(property, "AttentionIconName") == 0) {
    return g_variant_new_string("");
  }
  if (g_strcmp0(property, "ToolTip") == 0) {
    return build_tooltip(self);
  }
  if (g_strcmp0(property, "ItemIsMenu") == 0) {
    // A host that reads this as true opens the menu on a primary click, which
    // is the behaviour this item exists to avoid.
    return g_variant_new_boolean(FALSE);
  }
  if (g_strcmp0(property, "Menu") == 0) {
    return g_variant_new_object_path(kMenuPath);
  }
  return nullptr;
}

static void notify_activate(StatusNotifierItem* self) {
  if (self->callbacks.on_activate != nullptr) {
    self->callbacks.on_activate(self->user_data);
  }
}

static void method_call_cb(GDBusConnection*,
                           const gchar*,
                           const gchar*,
                           const gchar*,
                           const gchar* method,
                           GVariant*,
                           GDBusMethodInvocation* invocation,
                           gpointer user_data) {
  auto* self = static_cast<StatusNotifierItem*>(user_data);
  if (g_strcmp0(method, "Activate") == 0 ||
      g_strcmp0(method, "SecondaryActivate") == 0) {
    notify_activate(self);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  if (g_strcmp0(method, "ContextMenu") == 0 ||
      g_strcmp0(method, "Scroll") == 0) {
    // The host renders the menu from the exported dbusmenu, and scrolling has
    // no meaning here.
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                        G_DBUS_ERROR_UNKNOWN_METHOD,
                                        "unknown method %s", method);
}

static const GDBusInterfaceVTable kItemVtable = {
    method_call_cb,
    get_property_cb,
    nullptr,
    {},
};

static void register_with_watcher(StatusNotifierItem* self) {
  if (!self->name_acquired || self->bus == nullptr) {
    return;
  }
  g_dbus_connection_call(self->bus, kWatcherName, kWatcherPath, kWatcherName,
                         "RegisterStatusNotifierItem",
                         g_variant_new("(s)", self->bus_name), nullptr,
                         G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr, nullptr);
}

static void on_name_acquired(GDBusConnection*, const gchar*, gpointer user_data) {
  auto* self = static_cast<StatusNotifierItem*>(user_data);
  self->name_acquired = TRUE;
  register_with_watcher(self);
}

static void on_watcher_appeared(GDBusConnection*,
                                const gchar*,
                                const gchar*,
                                gpointer user_data) {
  // A panel restart drops every registration it held, so re-register instead
  // of waiting for a relaunch.
  register_with_watcher(static_cast<StatusNotifierItem*>(user_data));
}

static void menu_show_cb(gpointer user_data) {
  notify_activate(static_cast<StatusNotifierItem*>(user_data));
}

static void menu_quit_cb(gpointer user_data) {
  auto* self = static_cast<StatusNotifierItem*>(user_data);
  if (self->callbacks.on_quit != nullptr) {
    self->callbacks.on_quit(self->user_data);
  }
}

gboolean status_notifier_item_host_available() {
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) {
    return FALSE;
  }
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", kWatcherName), G_VARIANT_TYPE("(b)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
  if (reply == nullptr) {
    return FALSE;
  }
  gboolean has_owner = FALSE;
  g_variant_get(reply, "(b)", &has_owner);
  return has_owner;
}

StatusNotifierItem* status_notifier_item_new(
    const gchar* title,
    StatusNotifierItemCallbacks callbacks,
    gpointer user_data) {
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) {
    return nullptr;
  }
  g_autoptr(GDBusNodeInfo) info =
      g_dbus_node_info_new_for_xml(kInterfaceXml, nullptr);
  if (info == nullptr) {
    g_object_unref(bus);
    return nullptr;
  }
  auto* self = g_new0(StatusNotifierItem, 1);
  self->bus = bus;
  self->title = g_strdup(title);
  self->callbacks = callbacks;
  self->user_data = user_data;
  self->active = TRUE;
  self->registration = g_dbus_connection_register_object(
      bus, kItemPath, info->interfaces[0], &kItemVtable, self, nullptr,
      nullptr);
  if (self->registration == 0) {
    status_notifier_item_free(self);
    return nullptr;
  }
  g_autofree gchar* show_label = g_strdup_printf("Show %s", title);
  self->menu = status_notifier_menu_new(bus, kMenuPath, show_label,
                                        menu_show_cb, menu_quit_cb, self);
  if (self->menu == nullptr) {
    status_notifier_item_free(self);
    return nullptr;
  }
  // Hosts predating the unique-name form look the item up by this well-known
  // name, so own it before registering.
  self->bus_name = g_strdup_printf("org.kde.StatusNotifierItem-%d-1", getpid());
  self->owner_id = g_bus_own_name_on_connection(
      bus, self->bus_name, G_BUS_NAME_OWNER_FLAGS_NONE, on_name_acquired,
      nullptr, self, nullptr);
  self->watcher_watch = g_bus_watch_name(
      G_BUS_TYPE_SESSION, kWatcherName, G_BUS_NAME_WATCHER_FLAGS_NONE,
      on_watcher_appeared, nullptr, self, nullptr);
  return self;
}

void status_notifier_item_set_active(StatusNotifierItem* item,
                                     gboolean active) {
  if (item == nullptr || item->active == active) {
    return;
  }
  item->active = active;
  emit_signal(item, "NewStatus",
              g_variant_new("(s)", active ? "Active" : "Passive"));
}

void status_notifier_item_set_tooltip(StatusNotifierItem* item,
                                      const gchar* tooltip) {
  if (item == nullptr || g_strcmp0(item->tooltip, tooltip) == 0) {
    return;
  }
  g_free(item->tooltip);
  item->tooltip = g_strdup(tooltip);
  emit_signal(item, "NewToolTip", nullptr);
}

void status_notifier_item_set_badge_count(StatusNotifierItem* item, int count) {
  if (item == nullptr) {
    return;
  }
  const int clamped = count < 0 ? 0 : count;
  if (item->badge_count == clamped) {
    return;
  }
  item->badge_count = clamped;
  g_clear_pointer(&item->icon_pixmap, g_variant_unref);
  emit_signal(item, "NewIcon", nullptr);
}

void status_notifier_item_free(StatusNotifierItem* item) {
  if (item == nullptr) {
    return;
  }
  if (item->watcher_watch != 0) {
    g_bus_unwatch_name(item->watcher_watch);
  }
  if (item->owner_id != 0) {
    g_bus_unown_name(item->owner_id);
  }
  status_notifier_menu_free(item->menu);
  if (item->registration != 0 && item->bus != nullptr) {
    g_dbus_connection_unregister_object(item->bus, item->registration);
  }
  g_clear_pointer(&item->icon_pixmap, g_variant_unref);
  g_clear_object(&item->bus);
  g_clear_pointer(&item->bus_name, g_free);
  g_clear_pointer(&item->title, g_free);
  g_clear_pointer(&item->tooltip, g_free);
  g_free(item);
}
