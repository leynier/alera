import 'dart:async';

import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Channel the Linux (GTK) and Windows (Win32) runners use to forward native
/// application-menu activation into Dart. macOS does not use it: the
/// PlatformMenuBar callbacks already run in Dart.
const String nativeAppMenuChannelName = 'dev.leynier.alera/app_menu';

const MethodChannel nativeAppMenuChannel = MethodChannel(
  nativeAppMenuChannelName,
);

/// Method names invoked by the native runners. Keep in sync with
/// linux/runner/my_application.cc and windows/runner/win32_app_menu.cpp.
abstract final class NativeAppMenuMethod {
  static const String openSettings = 'openSettings';
  static const String checkForUpdates = 'checkForUpdates';
  static const String showAbout = 'showAbout';
  static const String exitApp = 'exitApp';
  static const String undo = 'undo';
  static const String redo = 'redo';
  static const String cut = 'cut';
  static const String copy = 'copy';
  static const String paste = 'paste';
  static const String selectAll = 'selectAll';
}

/// Dispatches a native menu activation to the shared app-menu actions.
Future<Object?> handleNativeAppMenuCall(
  MethodCall call, {
  required BuildContext context,
  required WidgetRef ref,
}) async {
  switch (call.method) {
    case NativeAppMenuMethod.openSettings:
      if (context.mounted) {
        unawaited(openAppMenuSettings(context));
      }
    case NativeAppMenuMethod.checkForUpdates:
      if (context.mounted) {
        unawaited(checkForUpdatesFromAppMenu(context, ref));
      }
    case NativeAppMenuMethod.showAbout:
      if (context.mounted) {
        unawaited(showAppMenuAbout(context, ref));
      }
    case NativeAppMenuMethod.exitApp:
      unawaited(exitAppFromMenu(ref));
    case NativeAppMenuMethod.undo:
      invokeFocusedTextIntent(
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
    case NativeAppMenuMethod.redo:
      invokeFocusedTextIntent(
        const RedoTextIntent(SelectionChangedCause.keyboard),
      );
    case NativeAppMenuMethod.cut:
      invokeFocusedTextIntent(
        const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
      );
    case NativeAppMenuMethod.copy:
      invokeFocusedTextIntent(CopySelectionTextIntent.copy);
    case NativeAppMenuMethod.paste:
      invokeFocusedTextIntent(
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
    case NativeAppMenuMethod.selectAll:
      invokeFocusedTextIntent(
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
  }
  return null;
}
