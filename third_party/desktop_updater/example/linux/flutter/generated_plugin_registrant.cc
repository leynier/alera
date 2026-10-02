//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <desktop_updater/desktop_updater_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) desktop_updater_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DesktopUpdaterPlugin");
  desktop_updater_plugin_register_with_registrar(desktop_updater_registrar);
}
