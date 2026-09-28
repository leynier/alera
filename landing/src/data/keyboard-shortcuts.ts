import type { KeyboardPlatform } from '../lib/key-chord-label';

/**
 * Every keyboard action the desktop app registers, with its default chords per
 * platform, in the order and groups of the app's registry
 * (lib/src/features/keyboard/domain/keyboard_action_definitions.dart). The
 * Keyboard Shortcuts docs page renders it; keyboard-shortcuts.test.ts fails
 * when it drifts from the registry.
 */
export interface ShortcutAction {
  id: string;
  label: string;
  description: string;
  bindings: Record<KeyboardPlatform, readonly string[]>;
  /** Still fires in a focused terminal when shortcuts are set to Terminal First (the default is App First). */
  inTerminal: boolean;
}

export interface ShortcutGroup {
  id: 'global' | 'workspace' | 'tabs' | 'panes';
  title: string;
  actions: readonly ShortcutAction[];
}

const uniform = (...chords: string[]): ShortcutAction['bindings'] => ({ macos: chords, windows: chords, linux: chords });

export const SHORTCUT_GROUPS: readonly ShortcutGroup[] = [
  {
    id: 'global',
    title: 'Global',
    actions: [
      { id: 'openSettings', label: 'Open Settings', description: 'Open the settings dialog.', bindings: uniform('Mod+Comma'), inTerminal: true },
      { id: 'openAutomations', label: 'Open Automations', description: 'Open the runtime-local automation manager.', bindings: uniform('Mod+Shift+A'), inTerminal: true },
      { id: 'openRunBoard', label: 'Open Run Board', description: 'Inspect orchestration runs across projects.', bindings: uniform(), inTerminal: true },
      { id: 'openQuickOpen', label: 'Quick Open', description: 'Search and open a file in the active workspace.', bindings: uniform('Mod+P'), inTerminal: true },
      { id: 'openCommandPalette', label: 'Command Palette', description: 'Search and run an Alera command.', bindings: uniform('Mod+Shift+P'), inTerminal: true },
      { id: 'addProject', label: 'Add Project', description: 'Open the add-project dialog.', bindings: uniform('Mod+Shift+O'), inTerminal: true },
      { id: 'toggleSidebar', label: 'Toggle Sidebar', description: 'Collapse or expand the project sidebar.', bindings: uniform('Mod+B'), inTerminal: true },
      { id: 'toggleContextPanel', label: 'Toggle Context Panel', description: 'Collapse or expand the Explorer, Search, Source Control and Pull Request panel.', bindings: uniform('Mod+Alt+B'), inTerminal: true },
      { id: 'showExplorer', label: 'Show Explorer', description: 'Open the Explorer panel for the active workspace.', bindings: uniform('Mod+Shift+E'), inTerminal: true },
      { id: 'showSourceControl', label: 'Show Source Control', description: 'Open the Source Control panel for the active workspace.', bindings: uniform('Mod+Shift+G'), inTerminal: true },
      { id: 'findInTerminal', label: 'Find in Terminal', description: 'Search the active terminal scrollback.', bindings: uniform('Mod+F'), inTerminal: true },
    ],
  },
  {
    id: 'workspace',
    title: 'Workspace',
    actions: [
      { id: 'createWorkspace', label: 'New Workspace', description: 'Create a linked workspace for the active Git project.', bindings: uniform('Mod+Shift+N'), inTerminal: true },
      { id: 'handOffWorkspace', label: 'Hand Off', description: 'Move the main worktree\'s current work into a new child workspace.', bindings: uniform(), inTerminal: true },
      { id: 'handOnWorkspace', label: 'Hand On', description: 'Bring a child worktree\'s current work back onto the main worktree.', bindings: uniform(), inTerminal: true },
      { id: 'navigateBack', label: 'Go Back', description: 'Go to the previously selected workspace.', bindings: { macos: ['Mod+BracketLeft'], windows: ['Alt+ArrowLeft'], linux: ['Alt+ArrowLeft'] }, inTerminal: false },
      { id: 'navigateForward', label: 'Go Forward', description: 'Go to the next workspace in navigation history.', bindings: { macos: ['Mod+BracketRight'], windows: ['Alt+ArrowRight'], linux: ['Alt+ArrowRight'] }, inTerminal: false },
      { id: 'previousWorkspace', label: 'Previous Workspace', description: 'Select the workspace above the active one in the sidebar.', bindings: uniform('Mod+Alt+ArrowUp'), inTerminal: true },
      { id: 'nextWorkspace', label: 'Next Workspace', description: 'Select the workspace below the active one in the sidebar.', bindings: uniform('Mod+Alt+ArrowDown'), inTerminal: true },
      { id: 'findInFiles', label: 'Find in Files', description: 'Open workspace search.', bindings: uniform('Mod+Shift+F'), inTerminal: true },
      { id: 'replaceInFiles', label: 'Replace in Files', description: 'Open workspace search and replace.', bindings: uniform('Mod+Shift+H'), inTerminal: true },
      { id: 'saveFile', label: 'Save File', description: 'Save the active editor file.', bindings: uniform('Mod+S'), inTerminal: false },
    ],
  },
  {
    id: 'tabs',
    title: 'Tabs',
    actions: [
      { id: 'toggleTerminalComposer', label: 'Toggle Terminal Composer', description: 'Show or hide the prompt composer for the active terminal.', bindings: uniform('Mod+Shift+Enter'), inTerminal: true },
      { id: 'newTerminalTab', label: 'New Terminal Tab', description: 'Open a terminal tab in the active workspace.', bindings: uniform('Mod+T'), inTerminal: false },
      { id: 'closeTab', label: 'Close Tab', description: 'Close the active tab.', bindings: uniform('Mod+W'), inTerminal: false },
      { id: 'nextTab', label: 'Next Tab', description: 'Select the next tab in the active pane.', bindings: { macos: ['Mod+Shift+BracketRight', 'Ctrl+Tab'], windows: ['Ctrl+Tab'], linux: ['Ctrl+Tab'] }, inTerminal: true },
      { id: 'previousTab', label: 'Previous Tab', description: 'Select the previous tab in the active pane.', bindings: { macos: ['Mod+Shift+BracketLeft', 'Ctrl+Shift+Tab'], windows: ['Ctrl+Shift+Tab'], linux: ['Ctrl+Shift+Tab'] }, inTerminal: true },
      { id: 'goToTab1', label: 'Go to Tab 1', description: 'Select the first tab in the active pane.', bindings: uniform('Mod+1'), inTerminal: true },
      { id: 'goToTab2', label: 'Go to Tab 2', description: 'Select the second tab in the active pane.', bindings: uniform('Mod+2'), inTerminal: true },
      { id: 'goToTab3', label: 'Go to Tab 3', description: 'Select the third tab in the active pane.', bindings: uniform('Mod+3'), inTerminal: true },
      { id: 'goToTab4', label: 'Go to Tab 4', description: 'Select the fourth tab in the active pane.', bindings: uniform('Mod+4'), inTerminal: true },
      { id: 'goToTab5', label: 'Go to Tab 5', description: 'Select the fifth tab in the active pane.', bindings: uniform('Mod+5'), inTerminal: true },
      { id: 'goToTab6', label: 'Go to Tab 6', description: 'Select the sixth tab in the active pane.', bindings: uniform('Mod+6'), inTerminal: true },
      { id: 'goToTab7', label: 'Go to Tab 7', description: 'Select the seventh tab in the active pane.', bindings: uniform('Mod+7'), inTerminal: true },
      { id: 'goToTab8', label: 'Go to Tab 8', description: 'Select the eighth tab in the active pane.', bindings: uniform('Mod+8'), inTerminal: true },
      { id: 'goToTab9', label: 'Go to Last Tab', description: 'Select the last tab in the active pane.', bindings: uniform('Mod+9'), inTerminal: true },
    ],
  },
  {
    id: 'panes',
    title: 'Panes',
    actions: [
      { id: 'splitRight', label: 'Split Right', description: 'Split the active pane to the right with a new terminal.', bindings: { macos: ['Mod+D'], windows: ['Mod+Shift+D'], linux: ['Mod+Shift+D'] }, inTerminal: false },
      { id: 'splitDown', label: 'Split Down', description: 'Split the active pane downward with a new terminal.', bindings: { macos: ['Mod+Shift+D'], windows: ['Mod+Alt+D'], linux: ['Mod+Alt+D'] }, inTerminal: false },
      { id: 'closeSplit', label: 'Close Split', description: 'Merge the active pane back into its sibling.', bindings: uniform('Mod+Shift+W'), inTerminal: true },
      { id: 'focusNextPane', label: 'Focus Next Pane', description: 'Move keyboard focus to the next pane, or into the active pane from the sidebar.', bindings: uniform('Mod+Alt+ArrowRight'), inTerminal: true },
      { id: 'focusPreviousPane', label: 'Focus Previous Pane', description: 'Move keyboard focus to the previous pane, or into the active pane from the sidebar.', bindings: uniform('Mod+Alt+ArrowLeft'), inTerminal: true },
    ],
  },
];
