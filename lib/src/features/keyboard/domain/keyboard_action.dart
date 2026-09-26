import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';

part 'keyboard_action.mapper.dart';
part 'keyboard_action_definitions.dart';

/// Decides who wins a key event while a terminal is focused.
@MappableEnum()
enum TerminalShortcutPolicy {
  /// Alera shortcuts intercept before the terminal sees the key.
  appFirst,

  /// The terminal receives every key except shortcuts explicitly marked
  /// [KeybindingDefinition.allowInTerminal].
  terminalFirst,
}

/// The three desktop platforms Alera targets, used to pick default bindings.
enum KeyboardPlatform {
  macos,
  windows,
  linux;

  static KeyboardPlatform get current {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => KeyboardPlatform.macos,
      TargetPlatform.windows => KeyboardPlatform.windows,
      _ => KeyboardPlatform.linux,
    };
  }

  bool get isMacOS => this == KeyboardPlatform.macos;
}

/// Visual grouping for the settings editor. Order here is the display order.
enum KeyboardActionGroup(this.label) {
  global('Global'),
  workspace('Workspace'),
  tabs('Tabs'),
  panes('Panes');

  final String label;
}

/// Every shortcut-able action. The string [name] is the stable persistence key.
@MappableEnum()
enum KeyboardActionId {
  openSettings,
  openAutomations,
  openRunBoard,
  openQuickOpen,
  openCommandPalette,
  addProject,
  toggleSidebar,
  toggleContextPanel,
  showExplorer,
  showSourceControl,
  createWorkspace,
  handOffWorkspace,
  handOnWorkspace,
  navigateBack,
  navigateForward,
  previousWorkspace,
  nextWorkspace,
  findInFiles,
  findInTerminal,
  toggleTerminalComposer,
  replaceInFiles,
  saveFile,
  newTerminalTab,
  closeTab,
  nextTab,
  previousTab,
  goToTab1,
  goToTab2,
  goToTab3,
  goToTab4,
  goToTab5,
  goToTab6,
  goToTab7,
  goToTab8,
  goToTab9,
  splitRight,
  splitDown,
  closeSplit,
  focusNextPane,
  focusPreviousPane;

  /// For `goToTabN` actions, the 1-based tab index; null otherwise.
  int? get tabIndex {
    return switch (this) {
      goToTab1 => 1,
      goToTab2 => 2,
      goToTab3 => 3,
      goToTab4 => 4,
      goToTab5 => 5,
      goToTab6 => 6,
      goToTab7 => 7,
      goToTab8 => 8,
      goToTab9 => 9,
      _ => null,
    };
  }
}

/// Canonical chord strings per platform.
class PlatformBindings {
  const new({required this.macos, required this.windows, required this.linux});

  /// Same binding(s) on every platform.
  const new uniform(List<String> bindings)
    : macos = bindings,
      windows = bindings,
      linux = bindings;

  final List<String> macos;
  final List<String> windows;
  final List<String> linux;

  List<String> forPlatform(KeyboardPlatform platform) {
    return switch (platform) {
      KeyboardPlatform.macos => macos,
      KeyboardPlatform.windows => windows,
      KeyboardPlatform.linux => linux,
    };
  }
}

/// A single action's metadata and default bindings.
class const KeybindingDefinition({
  required this.id,
  required this.label,
  required this.group,
  required this.description,
  required this.defaultBindings,
  this.searchKeywords = const <String>[],
  this.allowInTerminal = false,
}) {
  final KeyboardActionId id;
  final String label;
  final KeyboardActionGroup group;
  final String description;
  final PlatformBindings defaultBindings;
  final List<String> searchKeywords;

  /// Whether this binding still intercepts under [TerminalShortcutPolicy.terminalFirst].
  final bool allowInTerminal;
}

/// Definition lookup by id.
final Map<KeyboardActionId, KeybindingDefinition> keybindingDefinitionsById =
    <KeyboardActionId, KeybindingDefinition>{
      for (final definition in keybindingDefinitions) definition.id: definition,
    };
