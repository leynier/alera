import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/app_menu/infra/native_app_menu_channel.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Installs the desktop application menu.
///
/// - **macOS:** [PlatformMenuBar] (system menu bar; replaces MainMenu.xib).
/// - **Windows / Linux:** the runners install a native menu (Win32 `HMENU`,
///   GTK `GtkMenuBar`) and forward activation over [nativeAppMenuChannel];
///   this scope only registers the Dart-side handler.
class AleraAppMenuScope extends ConsumerWidget {
  const AleraAppMenuScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return child;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => _MacOsPlatformMenuBar(child: child),
      TargetPlatform.windows ||
      TargetPlatform.linux => _NativeAppMenuBridge(child: child),
      _ => child,
    };
  }
}

/// Linux/Windows install their menu in the native runner; this widget only
/// wires the channel that receives native menu activation.
class _NativeAppMenuBridge extends ConsumerStatefulWidget {
  const _NativeAppMenuBridge({required this.child});

  final Widget child;

  @override
  ConsumerState<_NativeAppMenuBridge> createState() =>
      _NativeAppMenuBridgeState();
}

class _NativeAppMenuBridgeState extends ConsumerState<_NativeAppMenuBridge> {
  @override
  void initState() {
    super.initState();
    nativeAppMenuChannel.setMethodCallHandler(_handleMenuCall);
  }

  @override
  void dispose() {
    nativeAppMenuChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Object?> _handleMenuCall(MethodCall call) {
    return handleNativeAppMenuCall(call, context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MacOsPlatformMenuBar extends ConsumerWidget {
  const _MacOsPlatformMenuBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch settings so the menu rebuilds when openSettings is remapped.
    ref.watch(settingsControllerProvider.select((s) => s.keyboard));

    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: kAleraAppName,
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'About $kAleraAppName',
              onSelected: () {
                unawaited(showAppMenuAbout(context));
              },
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Settings ...',
                  // Do not register a platform shortcut: Mod+Comma is already
                  // handled by KeyboardShortcutsScope. A duplicate native
                  // accelerator can open Settings twice.
                  onSelected: () {
                    unawaited(openAppMenuSettings(context));
                  },
                ),
                PlatformMenuItem(
                  label: 'Check for Updates ...',
                  onSelected: () {
                    unawaited(checkForUpdatesFromAppMenu(context, ref));
                  },
                ),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.servicesSubmenu,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu,
              ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.hide,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hide,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.hideOtherApplications,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hideOtherApplications,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.showAllApplications,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.showAllApplications,
                  ),
              ],
            ),
            // Use the app-window close path so Quit flushes window state the
            // same way Windows/Linux Exit does (platform terminate may skip it).
            PlatformMenuItem(
              label: 'Quit $kAleraAppName',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyQ,
                meta: true,
              ),
              onSelected: () {
                unawaited(exitAppFromMenu(ref));
              },
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Undo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const UndoTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const RedoTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const CopySelectionTextIntent.cut(
                        SelectionChangedCause.keyboard,
                      ),
                    );
                  },
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(CopySelectionTextIntent.copy);
                  },
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const PasteTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const SelectAllTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: <PlatformMenuItem>[
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.minimizeWindow,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.minimizeWindow,
              ),
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.zoomWindow,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.zoomWindow,
              ),
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.toggleFullScreen,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.toggleFullScreen,
              ),
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
              ),
          ],
        ),
      ],
      child: child,
    );
  }
}

