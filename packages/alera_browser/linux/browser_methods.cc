#include "browser_state.h"

#include <cstring>
#include <initializer_list>

namespace {

FlValue* probe_capabilities(AleraBrowserPlugin* plugin) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(
      value, "engine", fl_value_new_string("webKitGtk"));
  g_autofree gchar* version = g_strdup_printf(
      "%u.%u.%u", webkit_get_major_version(), webkit_get_minor_version(),
      webkit_get_micro_version());
  fl_value_set_string_take(
      value, "engineVersion", fl_value_new_string(version));
  const gboolean available = plugin->overlay != nullptr;
  const gchar* true_flags[] = {
      "engineAvailable",
      "pageSurface",
      "isolatedProfiles",
      "ephemeralProfiles",
      "deterministicPageClose",
      "navigation",
      "navigationEvents",
      "javascript",
      "basicCookies",
      "fullCookies",
      "permissionCallbacks",
      "tlsCallbacks",
      "popupCallbacks",
      "downloadCallbacks",
      "domSnapshot",
      "domActions",
      "nativeFileUpload",
      "viewportScreenshot",
      "fullPageScreenshot",
      "pdf",
      "flutterOverlayOcclusion",
      "atomicCookieImport",
      "manualJsonCookieImport",
  };
  for (const gchar* flag : true_flags) {
    fl_value_set_string_take(
        value, flag, fl_value_new_bool(available));
  }
  fl_value_set_string_take(
      value, "linuxGtkOverlay", fl_value_new_bool(available));
  fl_value_set_string_take(
      value, "crossOriginFrameAutomation", fl_value_new_bool(FALSE));
  fl_value_set_string_take(
      value, "trustedInputEvents", fl_value_new_bool(FALSE));
  fl_value_set_string_take(
      value, "tlsTrustScope", fl_value_new_string(
          available ? "profileSession" : "none"));
  FlValue* native_sources = fl_value_new_list();
  for (const gchar* source : {"chrome", "edge", "brave", "firefox"}) {
    fl_value_append_take(
        native_sources, fl_value_new_string(source));
  }
  fl_value_set_string_take(
      value, "nativeCookieImportSources", native_sources);
  FlValue* required_sources = fl_value_new_list();
  for (const gchar* source : {"chrome", "edge", "brave", "firefox"}) {
    fl_value_append_take(
        required_sources, fl_value_new_string(source));
  }
  fl_value_set_string_take(
      value, "requiredNativeCookieImportSources", required_sources);
  FlValue* limitations = fl_value_new_list();
  fl_value_append_take(
      limitations,
      fl_value_new_string("cross_origin_frames_unavailable"));
  fl_value_append_take(
      limitations,
      fl_value_new_string("trusted_input_events_unavailable"));
  fl_value_set_string_take(value, "limitations", limitations);
  return value;
}

}  // namespace

void browser_handle_method_call(AleraBrowserPlugin* plugin,
                                FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  if (std::strcmp(method, "probe") == 0) {
    g_autoptr(FlValue) value = probe_capabilities(plugin);
    browser_respond(method_call, browser_success(value));
  } else if (g_str_has_prefix(method, "profile.")) {
    browser_profile_handle_method(plugin, method_call, method, args);
  } else if (g_str_has_prefix(method, "page.")) {
    browser_page_handle_method(plugin, method_call, method, args);
  } else if (g_str_has_prefix(method, "cookies.")) {
    browser_cookie_handle_method(plugin, method_call, method, args);
  } else if (g_str_has_prefix(method, "capture.")) {
    browser_capture_handle_method(plugin, method_call, method, args);
  } else if (g_str_has_prefix(method, "cookieImport.")) {
    browser_import_handle_method(plugin, method_call, method, args);
  } else if (std::strcmp(method, "decision.resolve") == 0) {
    browser_decision_resolve(plugin, method_call, args);
  } else {
    browser_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
  }
}
