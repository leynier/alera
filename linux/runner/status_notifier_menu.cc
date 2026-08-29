#include "status_notifier_menu.h"

namespace {

constexpr gint kRootId = 0;
constexpr gint kShowId = 1;
constexpr gint kSeparatorId = 2;
constexpr gint kQuitId = 3;
// The menu never changes shape, so the layout revision is a constant and no
// LayoutUpdated signal is ever owed to the host.
constexpr guint kRevision = 1;

constexpr char kInterfaceXml[] =
    "<node>"
    "  <interface name='com.canonical.dbusmenu'>"
    "    <property name='Version' type='u' access='read'/>"
    "    <property name='TextDirection' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='IconThemePath' type='as' access='read'/>"
    "    <method name='GetLayout'>"
    "      <arg type='i' name='parentId' direction='in'/>"
    "      <arg type='i' name='recursionDepth' direction='in'/>"
    "      <arg type='as' name='propertyNames' direction='in'/>"
    "      <arg type='u' name='revision' direction='out'/>"
    "      <arg type='(ia{sv}av)' name='layout' direction='out'/>"
    "    </method>"
    "    <method name='GetGroupProperties'>"
    "      <arg type='ai' name='ids' direction='in'/>"
    "      <arg type='as' name='propertyNames' direction='in'/>"
    "      <arg type='a(ia{sv})' name='properties' direction='out'/>"
    "    </method>"
    "    <method name='GetProperty'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='s' name='name' direction='in'/>"
    "      <arg type='v' name='value' direction='out'/>"
    "    </method>"
    "    <method name='Event'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='s' name='eventId' direction='in'/>"
    "      <arg type='v' name='data' direction='in'/>"
    "      <arg type='u' name='timestamp' direction='in'/>"
    "    </method>"
    "    <method name='EventGroup'>"
    "      <arg type='a(isvu)' name='events' direction='in'/>"
    "      <arg type='ai' name='idErrors' direction='out'/>"
    "    </method>"
    "    <method name='AboutToShow'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='b' name='needUpdate' direction='out'/>"
    "    </method>"
    "    <method name='AboutToShowGroup'>"
    "      <arg type='ai' name='ids' direction='in'/>"
    "      <arg type='ai' name='updatesNeeded' direction='out'/>"
    "      <arg type='ai' name='idErrors' direction='out'/>"
    "    </method>"
    "    <signal name='ItemsPropertiesUpdated'>"
    "      <arg type='a(ia{sv})' name='updatedProps'/>"
    "      <arg type='a(ias)' name='removedProps'/>"
    "    </signal>"
    "    <signal name='LayoutUpdated'>"
    "      <arg type='u' name='revision'/>"
    "      <arg type='i' name='parent'/>"
    "    </signal>"
    "    <signal name='ItemActivationRequested'>"
    "      <arg type='i' name='id'/>"
    "      <arg type='u' name='timestamp'/>"
    "    </signal>"
    "  </interface>"
    "</node>";

}  // namespace

struct _StatusNotifierMenu {
  GDBusConnection* bus;
  guint registration;
  gchar* show_label;
  StatusNotifierMenuCallback on_show;
  StatusNotifierMenuCallback on_quit;
  gpointer user_data;
};

static void build_item_properties(StatusNotifierMenu* self,
                                  gint id,
                                  GVariantBuilder* properties) {
  g_variant_builder_init(properties, G_VARIANT_TYPE("a{sv}"));
  switch (id) {
    case kRootId:
      g_variant_builder_add(properties, "{sv}", "children-display",
                            g_variant_new_string("submenu"));
      return;
    case kSeparatorId:
      g_variant_builder_add(properties, "{sv}", "type",
                            g_variant_new_string("separator"));
      return;
    default:
      break;
  }
  const gchar* label = id == kQuitId ? "Quit" : self->show_label;
  g_variant_builder_add(properties, "{sv}", "label",
                        g_variant_new_string(label));
  g_variant_builder_add(properties, "{sv}", "enabled",
                        g_variant_new_boolean(TRUE));
  g_variant_builder_add(properties, "{sv}", "visible",
                        g_variant_new_boolean(TRUE));
}

static GVariant* build_leaf(StatusNotifierMenu* self, gint id) {
  GVariantBuilder properties;
  build_item_properties(self, id, &properties);
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
  return g_variant_new("(ia{sv}av)", id, &properties, &children);
}

static GVariant* build_layout(StatusNotifierMenu* self, gint parent_id) {
  if (parent_id != kRootId) {
    return build_leaf(self, parent_id);
  }
  GVariantBuilder properties;
  build_item_properties(self, kRootId, &properties);
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
  g_variant_builder_add(&children, "v", build_leaf(self, kShowId));
  g_variant_builder_add(&children, "v", build_leaf(self, kSeparatorId));
  g_variant_builder_add(&children, "v", build_leaf(self, kQuitId));
  return g_variant_new("(ia{sv}av)", kRootId, &properties, &children);
}

static void handle_get_group_properties(StatusNotifierMenu* self,
                                        GVariant* parameters,
                                        GDBusMethodInvocation* invocation) {
  g_autoptr(GVariant) ids = g_variant_get_child_value(parameters, 0);
  gsize count = 0;
  const gint32* requested =
      static_cast<const gint32*>(g_variant_get_fixed_array(ids, &count, sizeof(gint32)));
  const gint all[] = {kRootId, kShowId, kSeparatorId, kQuitId};
  GVariantBuilder result;
  g_variant_builder_init(&result, G_VARIANT_TYPE("a(ia{sv})"));
  for (gsize i = 0; i < (count == 0 ? G_N_ELEMENTS(all) : count); i += 1) {
    const gint id = count == 0 ? all[i] : requested[i];
    GVariantBuilder properties;
    build_item_properties(self, id, &properties);
    g_variant_builder_add(&result, "(ia{sv})", id, &properties);
  }
  g_dbus_method_invocation_return_value(invocation,
                                        g_variant_new("(a(ia{sv}))", &result));
}

static void handle_event(StatusNotifierMenu* self, GVariant* parameters) {
  gint32 id = 0;
  const gchar* event_id = nullptr;
  g_variant_get_child(parameters, 0, "i", &id);
  g_autoptr(GVariant) event = g_variant_get_child_value(parameters, 1);
  event_id = g_variant_get_string(event, nullptr);
  if (g_strcmp0(event_id, "clicked") != 0) {
    return;
  }
  if (id == kShowId && self->on_show != nullptr) {
    self->on_show(self->user_data);
  } else if (id == kQuitId && self->on_quit != nullptr) {
    self->on_quit(self->user_data);
  }
}

static void method_call_cb(GDBusConnection*,
                           const gchar*,
                           const gchar*,
                           const gchar*,
                           const gchar* method,
                           GVariant* parameters,
                           GDBusMethodInvocation* invocation,
                           gpointer user_data) {
  auto* self = static_cast<StatusNotifierMenu*>(user_data);
  if (g_strcmp0(method, "GetLayout") == 0) {
    gint32 parent_id = 0;
    g_variant_get_child(parameters, 0, "i", &parent_id);
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(u@(ia{sv}av))", kRevision,
                                  build_layout(self, parent_id)));
    return;
  }
  if (g_strcmp0(method, "GetGroupProperties") == 0) {
    handle_get_group_properties(self, parameters, invocation);
    return;
  }
  if (g_strcmp0(method, "GetProperty") == 0) {
    gint32 id = 0;
    const gchar* name = nullptr;
    g_variant_get(parameters, "(i&s)", &id, &name);
    GVariantBuilder properties;
    build_item_properties(self, id, &properties);
    g_autoptr(GVariant) map = g_variant_builder_end(&properties);
    g_autoptr(GVariant) value = g_variant_lookup_value(map, name, nullptr);
    g_dbus_method_invocation_return_value(
        invocation,
        g_variant_new("(v)", value != nullptr ? value
                                              : g_variant_new_string("")));
    return;
  }
  if (g_strcmp0(method, "Event") == 0) {
    handle_event(self, parameters);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  if (g_strcmp0(method, "EventGroup") == 0) {
    g_autoptr(GVariant) events = g_variant_get_child_value(parameters, 0);
    GVariantIter iter;
    g_variant_iter_init(&iter, events);
    g_autoptr(GVariant) entry = nullptr;
    while ((entry = g_variant_iter_next_value(&iter)) != nullptr) {
      handle_event(self, entry);
      g_clear_pointer(&entry, g_variant_unref);
    }
    GVariantBuilder errors;
    g_variant_builder_init(&errors, G_VARIANT_TYPE("ai"));
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(ai)", &errors));
    return;
  }
  if (g_strcmp0(method, "AboutToShow") == 0) {
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(b)", FALSE));
    return;
  }
  if (g_strcmp0(method, "AboutToShowGroup") == 0) {
    GVariantBuilder updates;
    g_variant_builder_init(&updates, G_VARIANT_TYPE("ai"));
    GVariantBuilder errors;
    g_variant_builder_init(&errors, G_VARIANT_TYPE("ai"));
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(aiai)", &updates, &errors));
    return;
  }
  g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                        G_DBUS_ERROR_UNKNOWN_METHOD,
                                        "unknown method %s", method);
}

static GVariant* get_property_cb(GDBusConnection*,
                                 const gchar*,
                                 const gchar*,
                                 const gchar*,
                                 const gchar* property,
                                 GError**,
                                 gpointer) {
  if (g_strcmp0(property, "Version") == 0) {
    return g_variant_new_uint32(3);
  }
  if (g_strcmp0(property, "TextDirection") == 0) {
    return g_variant_new_string("ltr");
  }
  if (g_strcmp0(property, "Status") == 0) {
    return g_variant_new_string("normal");
  }
  if (g_strcmp0(property, "IconThemePath") == 0) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("as"));
    return g_variant_builder_end(&builder);
  }
  return nullptr;
}

static const GDBusInterfaceVTable kMenuVtable = {
    method_call_cb,
    get_property_cb,
    nullptr,
    {},
};

StatusNotifierMenu* status_notifier_menu_new(
    GDBusConnection* bus,
    const gchar* object_path,
    const gchar* show_label,
    StatusNotifierMenuCallback on_show,
    StatusNotifierMenuCallback on_quit,
    gpointer user_data) {
  g_autoptr(GDBusNodeInfo) info =
      g_dbus_node_info_new_for_xml(kInterfaceXml, nullptr);
  if (info == nullptr) {
    return nullptr;
  }
  auto* self = g_new0(StatusNotifierMenu, 1);
  self->bus = G_DBUS_CONNECTION(g_object_ref(bus));
  self->show_label = g_strdup(show_label);
  self->on_show = on_show;
  self->on_quit = on_quit;
  self->user_data = user_data;
  self->registration = g_dbus_connection_register_object(
      bus, object_path, info->interfaces[0], &kMenuVtable, self, nullptr,
      nullptr);
  if (self->registration == 0) {
    status_notifier_menu_free(self);
    return nullptr;
  }
  return self;
}

void status_notifier_menu_free(StatusNotifierMenu* menu) {
  if (menu == nullptr) {
    return;
  }
  if (menu->registration != 0 && menu->bus != nullptr) {
    g_dbus_connection_unregister_object(menu->bus, menu->registration);
  }
  g_clear_object(&menu->bus);
  g_clear_pointer(&menu->show_label, g_free);
  g_free(menu);
}
