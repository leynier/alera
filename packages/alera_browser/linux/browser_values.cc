#include "browser_state.h"

FlMethodCodec* browser_method_codec() {
  static FlStandardMethodCodec* codec = nullptr;
  if (codec == nullptr) {
    codec = fl_standard_method_codec_new();
  }
  return FL_METHOD_CODEC(codec);
}

FlValue* browser_map_lookup(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

const gchar* browser_map_string(FlValue* map, const gchar* key) {
  FlValue* value = browser_map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

gboolean browser_map_bool(FlValue* map,
                          const gchar* key,
                          gboolean fallback) {
  FlValue* value = browser_map_lookup(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL
             ? fl_value_get_bool(value)
             : fallback;
}

double browser_map_double(FlValue* map,
                          const gchar* key,
                          double fallback) {
  FlValue* value = browser_map_lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return fallback;
}

gint64 browser_map_int(FlValue* map, const gchar* key, gint64 fallback) {
  FlValue* value = browser_map_lookup(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value)
             : fallback;
}

FlMethodResponse* browser_success(FlValue* value) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

FlMethodResponse* browser_error(const gchar* code, const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

void browser_respond(FlMethodCall* call, FlMethodResponse* response) {
  GError* error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("Failed to respond to Alera browser call: %s",
              error != nullptr ? error->message : "unknown");
  }
  g_clear_error(&error);
  g_object_unref(response);
}

FlValue* browser_event(const gchar* type, const gchar* page_id) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "type", fl_value_new_string(type));
  if (page_id != nullptr) {
    fl_value_set_string_take(value, "pageId", fl_value_new_string(page_id));
  }
  return value;
}

void browser_send_event(AleraBrowserPlugin* plugin, FlValue* event) {
  if (!plugin->event_listening) {
    fl_value_unref(event);
    return;
  }
  GError* error = nullptr;
  fl_event_channel_send(plugin->event_channel, event, nullptr, &error);
  if (error != nullptr) {
    g_warning("Failed to send Alera browser event: %s", error->message);
  }
  g_clear_error(&error);
  fl_value_unref(event);
}
