/**
 * The shortcuts the demo presses, as the macOS defaults the keyboard
 * registry declares (lib/src/features/keyboard/domain/keyboard_action_definitions.dart),
 * printed the way key_chord.dart does (`formatChord`). The fidelity tests
 * compare all three fields with the app.
 */
export const SHORTCUTS = {
  newWorkspace: { label: 'New Workspace', chord: 'Mod+Shift+N', keys: '⇧⌘N' },
  splitRight: { label: 'Split Right', chord: 'Mod+D', keys: '⌘D' },
  closeSplit: { label: 'Close Split', chord: 'Mod+Shift+W', keys: '⇧⌘W' },
  showSourceControl: { label: 'Show Source Control', chord: 'Mod+Shift+G', keys: '⇧⌘G' },
} as const;
