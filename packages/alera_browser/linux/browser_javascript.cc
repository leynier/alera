#include "browser_state.h"

namespace {

FlValue* serialize_javascript_result(JSCValue* value) {
  if (value == nullptr || jsc_value_is_null(value) ||
      jsc_value_is_undefined(value)) {
    return fl_value_new_null();
  }
  if (jsc_value_is_boolean(value)) {
    return fl_value_new_bool(jsc_value_to_boolean(value));
  }
  if (jsc_value_is_number(value)) {
    return fl_value_new_float(jsc_value_to_double(value));
  }
  if (jsc_value_is_string(value)) {
    g_autofree gchar* text = jsc_value_to_string(value);
    return fl_value_new_string(text != nullptr ? text : "");
  }
  g_autofree gchar* json = jsc_value_to_json(value, 0);
  return json != nullptr ? fl_value_new_string(json) : fl_value_new_null();
}

void javascript_finished_cb(GObject* object,
                            GAsyncResult* result,
                            gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  JSCValue* value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    browser_respond(
        method_call, browser_error("javascript_error", error->message));
    g_clear_error(&error);
    g_object_unref(method_call);
    return;
  }
  g_autoptr(FlValue) serialized = serialize_javascript_result(value);
  if (value != nullptr) {
    g_object_unref(value);
  }
  browser_respond(method_call, browser_success(serialized));
  g_object_unref(method_call);
}

}  // namespace

void browser_evaluate_javascript(WebKitWebView* web_view,
                                 const gchar* script,
                                 FlMethodCall* method_call) {
  if (script == nullptr) {
    browser_respond(
        method_call,
        browser_error("invalid_script", "JavaScript must not be null."));
    return;
  }
  g_object_ref(method_call);
  webkit_web_view_evaluate_javascript(
      web_view, script, -1, nullptr, nullptr, nullptr,
      javascript_finished_cb, method_call);
}
