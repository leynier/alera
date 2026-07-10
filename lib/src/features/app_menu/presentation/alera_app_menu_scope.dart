import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Installs the desktop application menu.
///
/// - **macOS:** [PlatformMenuBar] (system menu bar; replaces MainMenu.xib).
/// - **Windows / Linux:** Material [MenuBar] at the top of the window (Flutter
///   engine does not implement native platform menus on these platforms).
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
      TargetPlatform.linux => _DesktopMaterialMenuBar(child: child),
      _ => child,
    };
  }
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

class _DesktopMaterialMenuBar extends ConsumerWidget {
  const _DesktopMaterialMenuBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Rebuild when openSettings binding changes so the display shortcut stays
    // aligned with KeyboardShortcutsScope.
    ref.watch(settingsControllerProvider.select((s) => s.keyboard));
    final settingsShortcut = settingsMenuShortcut(ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: AleraTokens.surface,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: MenuBar(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll<Color>(
                  AleraTokens.surface,
                ),
                elevation: const WidgetStatePropertyAll<double>(0),
                shape: const WidgetStatePropertyAll<OutlinedBorder>(
                  RoundedRectangleBorder(),
                ),
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                  EdgeInsets.symmetric(horizontal: AleraTokens.space4),
                ),
              ),
              children: <Widget>[
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      onPressed: () {
                        unawaited(openAppMenuSettings(context));
                      },
                      shortcut: settingsShortcut,
                      child: const Text('Settings ...'),
                    ),
                    MenuItemButton(
                      onPressed: () {
                        unawaited(checkForUpdatesFromAppMenu(context, ref));
                      },
                      child: const Text('Check for Updates ...'),
                    ),
                    const Divider(),
                    MenuItemButton(
                      onPressed: () {
                        unawaited(showAppMenuAbout(context));
                      },
                      child: Text('About $kAleraAppName'),
                    ),
                    MenuItemButton(
                      onPressed: () {
                        unawaited(exitAppFromMenu(ref));
                      },
                      child: const Text('Exit'),
                    ),
                  ],
                  child: Text(
                    kAleraAppName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
