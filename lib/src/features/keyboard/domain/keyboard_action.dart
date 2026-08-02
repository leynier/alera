import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';

part 'keyboard_action.mapper.dart';

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
enum KeyboardActionGroup {
  global('Global'),
  workspace('Workspace'),
  tabs('Tabs'),
  panes('Panes');

  const KeyboardActionGroup(this.label);

  final String label;
}

/// Every shortcut-able action. The string [name] is the stable persistence key.
@MappableEnum()
enum KeyboardActionId {
  openSettings,
  openQuickOpen,
  openCommandPalette,
  addProject,
  toggleSidebar,
  createWorkspace,
  navigateBack,
  navigateForward,
  findInFiles,
  findInTerminal,
  toggleTerminalComposer,
  replaceInFiles,
  saveFile,
  newTerminalTab,
  newBrowserTab,
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
  closeSplit;

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
  const PlatformBindings({
    required this.macos,
    required this.windows,
    required this.linux,
  });

  /// Same binding(s) on every platform.
  const PlatformBindings.uniform(List<String> bindings)
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
class KeybindingDefinition {
  const KeybindingDefinition({
    required this.id,
    required this.label,
    required this.group,
    required this.description,
    required this.defaultBindings,
    this.searchKeywords = const <String>[],
    this.allowInTerminal = false,
  });

  final KeyboardActionId id;
  final String label;
  final KeyboardActionGroup group;
  final String description;
  final PlatformBindings defaultBindings;
  final List<String> searchKeywords;

  /// Whether this binding still intercepts under [TerminalShortcutPolicy.terminalFirst].
  final bool allowInTerminal;
}

/// The central registry. This is the single source of truth shared by the
/// resolver, the dispatcher, and the settings UI.
const List<KeybindingDefinition> keybindingDefinitions = <KeybindingDefinition>[
  KeybindingDefinition(
    id: KeyboardActionId.openSettings,
    label: 'Open Settings',
    group: KeyboardActionGroup.global,
    description: 'Open the settings dialog.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Comma']),
    searchKeywords: <String>['preferences', 'config'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.openQuickOpen,
    label: 'Quick Open',
    group: KeyboardActionGroup.global,
    description: 'Search and open a file in the active workspace.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+P']),
    searchKeywords: <String>['file', 'path', 'search', 'go to'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.openCommandPalette,
    label: 'Command Palette',
    group: KeyboardActionGroup.global,
    description: 'Search and run an Alera command.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+P']),
    searchKeywords: <String>['commands', 'actions', 'search', 'run'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.addProject,
    label: 'Add Project',
    group: KeyboardActionGroup.global,
    description: 'Open the add-project dialog.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+O']),
    searchKeywords: <String>['open', 'repository', 'folder', 'clone'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.toggleSidebar,
    label: 'Toggle Sidebar',
    group: KeyboardActionGroup.global,
    description: 'Collapse or expand the project sidebar.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+B']),
    searchKeywords: <String>['hide', 'show', 'panel'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.createWorkspace,
    label: 'New Workspace',
    group: KeyboardActionGroup.workspace,
    description: 'Create a linked workspace for the active Git project.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+N']),
    searchKeywords: <String>['worktree', 'branch'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.navigateBack,
    label: 'Go Back',
    group: KeyboardActionGroup.workspace,
    description: 'Go to the previously selected workspace.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+BracketLeft'],
      windows: <String>['Alt+ArrowLeft'],
      linux: <String>['Alt+ArrowLeft'],
    ),
    searchKeywords: <String>['history', 'previous', 'worktree'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.navigateForward,
    label: 'Go Forward',
    group: KeyboardActionGroup.workspace,
    description: 'Go to the next workspace in navigation history.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+BracketRight'],
      windows: <String>['Alt+ArrowRight'],
      linux: <String>['Alt+ArrowRight'],
    ),
    searchKeywords: <String>['history', 'next', 'worktree'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.findInFiles,
    label: 'Find in Files',
    group: KeyboardActionGroup.workspace,
    description: 'Open workspace search.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+F']),
    searchKeywords: <String>['search', 'grep'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.findInTerminal,
    label: 'Find in Terminal',
    group: KeyboardActionGroup.global,
    description: 'Search the active terminal scrollback.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+F']),
    searchKeywords: <String>['search', 'terminal', 'scrollback'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.toggleTerminalComposer,
    label: 'Toggle Terminal Composer',
    group: KeyboardActionGroup.tabs,
    description: 'Show or hide the prompt composer for the active terminal.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+Enter']),
    searchKeywords: <String>['prompt', 'compose', 'agent', 'terminal'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.replaceInFiles,
    label: 'Replace in Files',
    group: KeyboardActionGroup.workspace,
    description: 'Open workspace search and replace.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+H']),
    searchKeywords: <String>['search', 'replace'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.saveFile,
    label: 'Save File',
    group: KeyboardActionGroup.workspace,
    description: 'Save the active editor file.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+S']),
    searchKeywords: <String>['editor', 'write'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.newTerminalTab,
    label: 'New Terminal Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Open a terminal tab in the active workspace.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+T']),
    searchKeywords: <String>['terminal', 'shell'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.newBrowserTab,
    label: 'New Browser Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Open a local browser tab in the active workspace.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+B']),
    searchKeywords: <String>['browser', 'web', 'page'],
    allowInTerminal: true,
  ),
  KeybindingDefinition(
    id: KeyboardActionId.closeTab,
    label: 'Close Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Close the active terminal tab.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+W']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.nextTab,
    label: 'Next Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Select the next tab in the active pane.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+Shift+BracketRight', 'Ctrl+Tab'],
      windows: <String>['Ctrl+Tab'],
      linux: <String>['Ctrl+Tab'],
    ),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.previousTab,
    label: 'Previous Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Select the previous tab in the active pane.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+Shift+BracketLeft', 'Ctrl+Shift+Tab'],
      windows: <String>['Ctrl+Shift+Tab'],
      linux: <String>['Ctrl+Shift+Tab'],
    ),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab1,
    label: 'Go to Tab 1',
    group: KeyboardActionGroup.tabs,
    description: 'Select the first tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+1']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab2,
    label: 'Go to Tab 2',
    group: KeyboardActionGroup.tabs,
    description: 'Select the second tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+2']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab3,
    label: 'Go to Tab 3',
    group: KeyboardActionGroup.tabs,
    description: 'Select the third tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+3']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab4,
    label: 'Go to Tab 4',
    group: KeyboardActionGroup.tabs,
    description: 'Select the fourth tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+4']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab5,
    label: 'Go to Tab 5',
    group: KeyboardActionGroup.tabs,
    description: 'Select the fifth tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+5']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab6,
    label: 'Go to Tab 6',
    group: KeyboardActionGroup.tabs,
    description: 'Select the sixth tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+6']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab7,
    label: 'Go to Tab 7',
    group: KeyboardActionGroup.tabs,
    description: 'Select the seventh tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+7']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab8,
    label: 'Go to Tab 8',
    group: KeyboardActionGroup.tabs,
    description: 'Select the eighth tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+8']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.goToTab9,
    label: 'Go to Last Tab',
    group: KeyboardActionGroup.tabs,
    description: 'Select the last tab in the active pane.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+9']),
  ),
  KeybindingDefinition(
    id: KeyboardActionId.splitRight,
    label: 'Split Right',
    group: KeyboardActionGroup.panes,
    description: 'Split the active pane to the right with a new terminal.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+D'],
      windows: <String>['Mod+Shift+D'],
      linux: <String>['Mod+Shift+D'],
    ),
    searchKeywords: <String>['pane', 'vertical'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.splitDown,
    label: 'Split Down',
    group: KeyboardActionGroup.panes,
    description: 'Split the active pane downward with a new terminal.',
    defaultBindings: PlatformBindings(
      macos: <String>['Mod+Shift+D'],
      windows: <String>['Mod+Alt+D'],
      linux: <String>['Mod+Alt+D'],
    ),
    searchKeywords: <String>['pane', 'horizontal'],
  ),
  KeybindingDefinition(
    id: KeyboardActionId.closeSplit,
    label: 'Close Split',
    group: KeyboardActionGroup.panes,
    description: 'Merge the active pane back into its sibling.',
    defaultBindings: PlatformBindings.uniform(<String>['Mod+Shift+W']),
    searchKeywords: <String>['merge', 'pane'],
  ),
];

/// Definition lookup by id.
final Map<KeyboardActionId, KeybindingDefinition> keybindingDefinitionsById =
    <KeyboardActionId, KeybindingDefinition>{
      for (final definition in keybindingDefinitions) definition.id: definition,
    };
