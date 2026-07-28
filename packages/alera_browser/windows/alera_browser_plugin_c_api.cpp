#include "include/alera_browser/alera_browser_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "alera_browser_plugin.h"

void AleraBrowserPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  alera_browser::AleraBrowserPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
