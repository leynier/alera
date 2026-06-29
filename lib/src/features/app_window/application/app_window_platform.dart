import 'package:flutter/foundation.dart';

bool get supportsDesktopAppWindowState {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
}
