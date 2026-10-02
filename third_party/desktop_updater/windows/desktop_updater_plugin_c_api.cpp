#include "include/desktop_updater/desktop_updater_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "desktop_updater_plugin.h"

void DesktopUpdaterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  desktop_updater::DesktopUpdaterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
