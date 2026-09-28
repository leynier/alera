/**
 * The shortcuts the demo presses, as the macOS defaults the keyboard
 * registry declares (lib/src/features/keyboard/domain/keyboard_action_definitions.dart)
 * and in the order key_chord.dart prints modifiers on macOS: ⌃⌥⇧⌘, then the
 * key. The fidelity tests compare all three fields with that file.
 */
export const SHORTCUTS = {
  newWorkspace: { label: 'New Workspace', chord: 'Mod+Shift+N', keys: '⇧⌘N' },
  splitRight: { label: 'Split Right', chord: 'Mod+D', keys: '⌘D' },
  closeSplit: { label: 'Close Split', chord: 'Mod+Shift+W', keys: '⇧⌘W' },
  showSourceControl: { label: 'Show Source Control', chord: 'Mod+Shift+G', keys: '⇧⌘G' },
} as const;

const MAC_MODIFIERS: readonly [string, string][] = [
  ['Ctrl', '⌃'],
  ['Alt', '⌥'],
  ['Shift', '⇧'],
  ['Mod', '⌘'],
];

/** A registry chord such as `Mod+Shift+N`, printed the way macOS shows it. */
export function macKeys(chord: string): string {
  const parts = chord.split('+');
  const key = parts.pop()!;
  return MAC_MODIFIERS.filter(([name]) => parts.includes(name)).map(([, glyph]) => glyph).join('') + key;
}
