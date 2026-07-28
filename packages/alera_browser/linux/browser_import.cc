#include "browser_state.h"

#include "browser_import_internal.h"

#include <cstring>
#include <initializer_list>

namespace {

struct ImportCall {
  FlMethodCall* call;
  gchar* profile_id;
  gchar* source;
  gchar* source_profile_name;
  gchar* json;
  BrowserCookieImportBatch* batch;
};

struct ProbeCall {
  FlMethodCall* call;
};

struct ProbeProfiles {
  GPtrArray* profiles[4] = {};
};

ImportCall* import_call_new(FlMethodCall* call,
                            const gchar* profile_id,
                            const gchar* source,
                            const gchar* source_profile_name,
                            const gchar* json) {
  ImportCall* context = g_new0(ImportCall, 1);
  context->call = FL_METHOD_CALL(g_object_ref(call));
  context->profile_id = g_strdup(profile_id);
  context->source = g_strdup(source);
  context->source_profile_name = g_strdup(source_profile_name);
  context->json = g_strdup(json);
  return context;
}

void import_call_free(ImportCall* context) {
  if (context == nullptr) {
    return;
  }
  g_clear_object(&context->call);
  g_clear_pointer(&context->profile_id, g_free);
  g_clear_pointer(&context->source, g_free);
  g_clear_pointer(&context->source_profile_name, g_free);
  g_clear_pointer(&context->json, g_free);
  browser_cookie_import_batch_free(context->batch);
  g_free(context);
}

ProbeCall* probe_call_new(FlMethodCall* call) {
  ProbeCall* context = g_new0(ProbeCall, 1);
  context->call = FL_METHOD_CALL(g_object_ref(call));
  return context;
}

void probe_call_free(ProbeCall* context) {
  if (context == nullptr) {
    return;
  }
  g_clear_object(&context->call);
  g_free(context);
}

void probe_profiles_free(ProbeProfiles* value) {
  if (value == nullptr) {
    return;
  }
  for (auto*& profiles : value->profiles) {
    g_clear_pointer(&profiles, g_ptr_array_unref);
  }
  delete value;
}

gboolean native_source(const gchar* source) {
  return g_strcmp0(source, "chrome") == 0 ||
         g_strcmp0(source, "edge") == 0 ||
         g_strcmp0(source, "brave") == 0 ||
         g_strcmp0(source, "firefox") == 0;
}

FlValue* import_result(const ImportCall* context, const gchar* outcome) {
  FlValue* result = fl_value_new_map();
  fl_value_set_string_take(
      result, "outcome", fl_value_new_string(outcome));
  const guint imported =
      context->batch != nullptr ? context->batch->imported_count : 0;
  const guint skipped =
      context->batch != nullptr ? context->batch->skipped_count : 0;
  fl_value_set_string_take(
      result, "importedCount", fl_value_new_int(imported));
  fl_value_set_string_take(
      result, "skippedCount", fl_value_new_int(skipped));
  if (context->batch != nullptr &&
      context->batch->detail_code != nullptr) {
    fl_value_set_string_take(
        result, "detailCode",
        fl_value_new_string(context->batch->detail_code));
  }
  return result;
}

void respond_import(ImportCall* context, const gchar* outcome) {
  g_autoptr(FlValue) result = import_result(context, outcome);
  browser_respond(context->call, browser_success(result));
}

void read_import_source(GTask* task,
                        gpointer source_object,
                        gpointer task_data,
                        GCancellable* cancellable) {
  ImportCall* context = static_cast<ImportCall*>(task_data);
  BrowserCookieImportBatch* batch = nullptr;
  if (g_strcmp0(context->source, "manualJson") == 0) {
    batch = browser_cookie_import_parse_json(context->json);
  } else {
    g_autoptr(GPtrArray) profiles =
        browser_cookie_import_find_profiles(context->source);
    g_autofree gchar* selection_error = nullptr;
    const auto* selected = browser_cookie_import_select_profile(
        profiles, context->source_profile_name, &selection_error);
    if (selected == nullptr) {
      batch = browser_cookie_import_batch_new();
      batch->detail_code = g_steal_pointer(&selection_error);
    } else if (g_strcmp0(context->source, "firefox") == 0) {
      batch = browser_cookie_import_read_firefox(
          selected->database_path);
    } else {
      batch = browser_cookie_import_read_chromium(
          context->source, selected->database_path);
    }
  }
  g_task_return_pointer(
      task, batch,
      reinterpret_cast<GDestroyNotify>(browser_cookie_import_batch_free));
}

void replace_import_done(GObject* object,
                         GAsyncResult* result,
                         gpointer user_data) {
  ImportCall* context = static_cast<ImportCall*>(user_data);
  GError* error = nullptr;
  const gboolean replaced = webkit_cookie_manager_replace_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (!replaced) {
    g_clear_pointer(&context->batch->detail_code, g_free);
    context->batch->detail_code = g_strdup("atomic_replace_failed");
    respond_import(context, "failed");
  } else {
    respond_import(
        context, context->batch->skipped_count > 0
                     ? "partiallyImported"
                     : "imported");
  }
  g_clear_error(&error);
  import_call_free(context);
}

void import_source_read_done(GObject* object,
                             GAsyncResult* result,
                             gpointer user_data) {
  AleraBrowserPlugin* plugin =
      reinterpret_cast<AleraBrowserPlugin*>(object);
  ImportCall* context = static_cast<ImportCall*>(user_data);
  context->batch = static_cast<BrowserCookieImportBatch*>(
      g_task_propagate_pointer(G_TASK(result), nullptr));
  if (context->batch == nullptr) {
    context->batch = browser_cookie_import_batch_new();
    context->batch->detail_code = g_strdup("source_read_failed");
    respond_import(context, "failed");
    import_call_free(context);
    return;
  }
  if (context->batch->unavailable) {
    respond_import(context, "unavailable");
    import_call_free(context);
    return;
  }
  if (context->batch->imported_count == 0 &&
      (context->batch->skipped_count > 0 ||
       context->batch->detail_code != nullptr)) {
    respond_import(context, "failed");
    import_call_free(context);
    return;
  }
  LinuxBrowserProfile* profile =
      static_cast<LinuxBrowserProfile*>(
          g_hash_table_lookup(plugin->profiles, context->profile_id));
  if (profile == nullptr) {
    g_clear_pointer(&context->batch->detail_code, g_free);
    context->batch->detail_code = g_strdup("profile_not_found");
    respond_import(context, "failed");
    import_call_free(context);
    return;
  }
  WebKitCookieManager* manager =
      webkit_web_context_get_cookie_manager(profile->context);
  webkit_cookie_manager_replace_cookies(
      manager, context->batch->cookies, nullptr, replace_import_done, context);
}

void start_import(AleraBrowserPlugin* plugin,
                  FlMethodCall* call,
                  const gchar* profile_id,
                  const gchar* source,
                  const gchar* source_profile_name,
                  const gchar* json) {
  ImportCall* context =
      import_call_new(
          call, profile_id, source, source_profile_name, json);
  GTask* task =
      g_task_new(plugin, nullptr, import_source_read_done, context);
  g_task_set_task_data(task, context, nullptr);
  g_task_run_in_thread(task, read_import_source);
  g_object_unref(task);
}

FlValue* source_status(const gchar* source,
                       gboolean supported,
                       gboolean available,
                       GPtrArray* profiles = nullptr,
                       const gchar* detail_code = nullptr) {
  FlValue* status = fl_value_new_map();
  fl_value_set_string_take(
      status, "source", fl_value_new_string(source));
  fl_value_set_string_take(
      status, "supported", fl_value_new_bool(supported));
  fl_value_set_string_take(
      status, "available", fl_value_new_bool(available));
  FlValue* profile_names = fl_value_new_list();
  if (profiles != nullptr) {
    for (guint index = 0; index < profiles->len; ++index) {
      const auto* profile =
          static_cast<BrowserCookieImportProfile*>(
              g_ptr_array_index(profiles, index));
      fl_value_append_take(
          profile_names, fl_value_new_string(profile->name));
    }
  }
  fl_value_set_string_take(
      status, "profileNames", profile_names);
  if (detail_code != nullptr) {
    fl_value_set_string_take(
        status, "detailCode", fl_value_new_string(detail_code));
  }
  return status;
}

void read_probe_sources(GTask* task,
                        gpointer source_object,
                        gpointer task_data,
                        GCancellable* cancellable) {
  auto* value = new ProbeProfiles();
  guint index = 0;
  for (const gchar* source : {"chrome", "edge", "brave", "firefox"}) {
    value->profiles[index] =
        browser_cookie_import_find_profiles(source);
    index++;
  }
  g_task_return_pointer(
      task, value,
      reinterpret_cast<GDestroyNotify>(probe_profiles_free));
}

void probe_sources_done(GObject* object,
                        GAsyncResult* result,
                        gpointer user_data) {
  ProbeCall* context = static_cast<ProbeCall*>(user_data);
  g_autoptr(GError) error = nullptr;
  auto* values = static_cast<ProbeProfiles*>(
      g_task_propagate_pointer(G_TASK(result), &error));
  g_autoptr(FlValue) statuses = fl_value_new_list();
  guint index = 0;
  for (const gchar* source : {"chrome", "edge", "brave", "firefox"}) {
    GPtrArray* profiles =
        values == nullptr ? nullptr : values->profiles[index];
    const gboolean available =
        profiles != nullptr && profiles->len > 0;
    fl_value_append_take(
        statuses,
        source_status(source, TRUE, available,
                      profiles,
                      available ? nullptr : "source_not_found"));
    index++;
  }
  fl_value_append_take(
      statuses, source_status("manualJson", TRUE, TRUE));
  probe_profiles_free(values);
  browser_respond(context->call, browser_success(statuses));
  probe_call_free(context);
}

void start_probe(AleraBrowserPlugin* plugin, FlMethodCall* call) {
  ProbeCall* context = probe_call_new(call);
  GTask* task =
      g_task_new(plugin, nullptr, probe_sources_done, context);
  g_task_run_in_thread(task, read_probe_sources);
  g_object_unref(task);
}

}  // namespace

void browser_import_handle_method(AleraBrowserPlugin* plugin,
                                  FlMethodCall* method_call,
                                  const gchar* method,
  FlValue* args) {
  if (std::strcmp(method, "cookieImport.probe") == 0) {
    start_probe(plugin, method_call);
    return;
  }
  if (std::strcmp(method, "cookieImport.run") != 0) {
    browser_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
    return;
  }
  const gchar* profile_id = browser_map_string(args, "profileId");
  const gchar* source = browser_map_string(args, "source");
  const gchar* source_profile_name =
      browser_map_string(args, "sourceProfileName");
  const gchar* json = browser_map_string(args, "json");
  if (profile_id == nullptr ||
      !g_hash_table_contains(plugin->profiles, profile_id)) {
    browser_respond(
        method_call,
        browser_error("profile_not_found",
                      "The browser profile does not exist."));
    return;
  }
  if (!native_source(source) && g_strcmp0(source, "manualJson") != 0) {
    ImportCall* context =
        import_call_new(
            method_call, profile_id, source, nullptr, nullptr);
    context->batch = browser_cookie_import_batch_new();
    context->batch->detail_code = g_strdup("source_unsupported");
    respond_import(context, "unsupported");
    import_call_free(context);
    return;
  }
  if (g_strcmp0(source, "manualJson") == 0 && json == nullptr) {
    browser_respond(
        method_call,
        browser_error("invalid_json", "Manual cookie JSON is required."));
    return;
  }
  start_import(
      plugin, method_call, profile_id, source,
      source_profile_name, json);
}
