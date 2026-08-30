import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/app_menu/infra/native_app_menu_channel.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:alera/src/features/orchestration/presentation/run_policy_review_dialog.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Installs the desktop application menu.
///
/// - **macOS:** [PlatformMenuBar] (system menu bar; replaces MainMenu.xib).
/// - **Windows / Linux:** [AleraAppMenuButton] provides the in-window menu;
///   this scope keeps the native channel bridge for backwards compatibility.
class const AleraAppMenuScope({super.key, required final Widget child})
    extends ConsumerWidget {
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
class const _NativeAppMenuBridge({required final Widget child})
    extends ConsumerStatefulWidget {
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

enum _AppMenuAction {
  openSettings,
  openAutomations,
  reviewExecutionPlans,
  checkForUpdates,
  undo,
  redo,
  cut,
  copy,
  paste,
  selectAll,
  showAbout,
  exitApp,
}

/// Compact application menu shown beside the app name on Windows and Linux.
/// macOS keeps these commands in the system menu bar instead.
class const AleraAppMenuButton({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AleraAppMenuButton> createState() => _AleraAppMenuButtonState();
}

class _AleraAppMenuButtonState extends ConsumerState<AleraAppMenuButton> {
  final _buttonKey = GlobalKey();
  FocusNode? _pointerFocusNode;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _openMenu() async {
    final focusNode = _pointerFocusNode ?? primaryFocus;
    _pointerFocusNode = null;
    final focusContext = focusNode?.context;
    final button = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) {
      return;
    }

    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_AppMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      requestFocus: false,
      items: const <PopupMenuEntry<_AppMenuAction>>[
        AleraDropdownEntry<_AppMenuAction>(
          value: .openSettings,
          label: 'Settings',
        ),
        AleraDropdownEntry<_AppMenuAction>(
          value: .openAutomations,
          label: 'Automations',
        ),
        AleraDropdownEntry<_AppMenuAction>(
          value: .reviewExecutionPlans,
          label: 'Execution Plans',
        ),
        AleraDropdownEntry<_AppMenuAction>(
          value: .checkForUpdates,
          label: 'Check for Updates',
        ),
        PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<_AppMenuAction>(value: .undo, label: 'Undo'),
        AleraDropdownEntry<_AppMenuAction>(value: .redo, label: 'Redo'),
        PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<_AppMenuAction>(value: .cut, label: 'Cut'),
        AleraDropdownEntry<_AppMenuAction>(value: .copy, label: 'Copy'),
        AleraDropdownEntry<_AppMenuAction>(value: .paste, label: 'Paste'),
        AleraDropdownEntry<_AppMenuAction>(
          value: .selectAll,
          label: 'Select All',
        ),
        PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<_AppMenuAction>(
          value: .showAbout,
          label: 'About $kAleraAppName',
        ),
        AleraDropdownEntry<_AppMenuAction>(value: .exitApp, label: 'Exit'),
      ],
    );
    if (selected == null || !mounted) {
      return;
    }
    void invokeEditIntent(Intent intent) {
      if (focusContext != null && focusContext.mounted) {
        focusNode?.requestFocus();
        invokeFocusedTextIntent(intent, focusContext: focusContext);
      }
    }

    switch (selected) {
      case _AppMenuAction.openSettings:
        await openAppMenuSettings(context);
      case _AppMenuAction.openAutomations:
        await openAutomationsDialog(context);
      case _AppMenuAction.reviewExecutionPlans:
        await showRunPolicyReviewDialog(context);
      case _AppMenuAction.checkForUpdates:
        await checkForUpdatesFromAppMenu(context, ref);
      case _AppMenuAction.undo:
        invokeEditIntent(const UndoTextIntent(.keyboard));
      case _AppMenuAction.redo:
        invokeEditIntent(const RedoTextIntent(.keyboard));
      case _AppMenuAction.cut:
        invokeEditIntent(const CopySelectionTextIntent.cut(.keyboard));
      case _AppMenuAction.copy:
        invokeEditIntent(CopySelectionTextIntent.copy);
      case _AppMenuAction.paste:
        invokeEditIntent(const PasteTextIntent(.keyboard));
      case _AppMenuAction.selectAll:
        invokeEditIntent(const SelectAllTextIntent(.keyboard));
      case _AppMenuAction.showAbout:
        await showAppMenuAbout(context, ref);
      case _AppMenuAction.exitApp:
        await exitAppFromMenu(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform) {
      return const SizedBox.shrink();
    }
    return Listener(
      onPointerDown: (_) => _pointerFocusNode = primaryFocus,
      child: KeyedSubtree(
        key: _buttonKey,
        child: AleraIconButton(
          tooltip: 'Application Menu',
          onPressed: () => unawaited(_openMenu()),
          icon: AleraIcons.more,
          minSize: 28,
        ),
      ),
    );
  }
}

class const _MacOsPlatformMenuBar({required final Widget child})
    extends ConsumerWidget {
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
                unawaited(showAppMenuAbout(context, ref));
              },
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Settings',
                  // Do not register a platform shortcut: Mod+Comma is already
                  // handled by KeyboardShortcutsScope. A duplicate native
                  // accelerator can open Settings twice.
                  onSelected: () {
                    unawaited(openAppMenuSettings(context));
                  },
                ),
                PlatformMenuItem(
                  label: 'Automations',
                  onSelected: () {
                    unawaited(openAutomationsDialog(context));
                  },
                ),
                PlatformMenuItem(
                  label: 'Execution Plans',
                  onSelected: () {
                    unawaited(showRunPolicyReviewDialog(context));
                  },
                ),
                PlatformMenuItem(
                  label: 'Check for Updates',
                  onSelected: () {
                    unawaited(checkForUpdatesFromAppMenu(context, ref));
                  },
                ),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(.servicesSubmenu))
              const PlatformProvidedMenuItem(type: .servicesSubmenu),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                if (PlatformProvidedMenuItem.hasMenu(.hide))
                  const PlatformProvidedMenuItem(type: .hide),
                if (PlatformProvidedMenuItem.hasMenu(.hideOtherApplications))
                  const PlatformProvidedMenuItem(type: .hideOtherApplications),
                if (PlatformProvidedMenuItem.hasMenu(.showAllApplications))
                  const PlatformProvidedMenuItem(type: .showAllApplications),
              ],
            ),
            // Use the app-window close path so Quit flushes window state the
            // same way Windows/Linux Exit does (platform terminate may skip it).
            PlatformMenuItem(
              label: 'Quit $kAleraAppName',
              shortcut: const SingleActivator(.keyQ, meta: true),
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
                  shortcut: const SingleActivator(.keyZ, meta: true),
                  onSelected: () {
                    invokeFocusedTextIntent(const UndoTextIntent(.keyboard));
                  },
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(
                    .keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () {
                    invokeFocusedTextIntent(const RedoTextIntent(.keyboard));
                  },
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(.keyX, meta: true),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const CopySelectionTextIntent.cut(.keyboard),
                    );
                  },
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: const SingleActivator(.keyC, meta: true),
                  onSelected: () {
                    invokeFocusedTextIntent(CopySelectionTextIntent.copy);
                  },
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(.keyV, meta: true),
                  onSelected: () {
                    invokeFocusedTextIntent(const PasteTextIntent(.keyboard));
                  },
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(.keyA, meta: true),
                  onSelected: () {
                    invokeFocusedTextIntent(
                      const SelectAllTextIntent(.keyboard),
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
            if (PlatformProvidedMenuItem.hasMenu(.minimizeWindow))
              const PlatformProvidedMenuItem(type: .minimizeWindow),
            if (PlatformProvidedMenuItem.hasMenu(.zoomWindow))
              const PlatformProvidedMenuItem(type: .zoomWindow),
            if (PlatformProvidedMenuItem.hasMenu(.toggleFullScreen))
              const PlatformProvidedMenuItem(type: .toggleFullScreen),
            if (PlatformProvidedMenuItem.hasMenu(.arrangeWindowsInFront))
              const PlatformProvidedMenuItem(type: .arrangeWindowsInFront),
          ],
        ),
      ],
      child: child,
    );
  }
}
