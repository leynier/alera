/**
 * Prints a registry chord such as `Mod+Shift+BracketRight` the way the app's
 * key_chord.dart formats it: macOS as glyphs without separators (⌃⌥⇧⌘, then
 * the key), Windows and Linux as `Ctrl+Shift+]`. `Mod` is ⌘ on macOS and Ctrl
 * elsewhere.
 */
export type KeyboardPlatform = 'macos' | 'windows' | 'linux';

/** Keys the app prints as a symbol instead of their token (`_displayLabels`). */
export const KEY_DISPLAY_LABELS: Readonly<Record<string, string>> = {
  Comma: ',',
  Period: '.',
  Slash: '/',
  Backslash: '\\',
  BracketLeft: '[',
  BracketRight: ']',
  Minus: '-',
  Equal: '=',
  Semicolon: ';',
  Quote: "'",
  Backquote: '`',
  Tab: 'Tab',
  Enter: 'Enter',
  Escape: 'Esc',
  Space: 'Space',
  Backspace: 'Backspace',
  Delete: 'Delete',
  Insert: 'Insert',
  Home: 'Home',
  End: 'End',
  PageUp: 'PageUp',
  PageDown: 'PageDown',
  ArrowUp: '↑',
  ArrowDown: '↓',
  ArrowLeft: '←',
  ArrowRight: '→',
};

export function formatChord(chord: string, platform: KeyboardPlatform): string {
  const tokens = chord.split('+');
  const key = tokens.pop() ?? '';
  const has = (modifier: string) => tokens.includes(modifier);
  const label = KEY_DISPLAY_LABELS[key] ?? key;
  if (platform === 'macos') {
    return `${has('Ctrl') ? '⌃' : ''}${has('Alt') ? '⌥' : ''}${has('Shift') ? '⇧' : ''}${has('Mod') || has('Cmd') ? '⌘' : ''}${label}`;
  }
  return [has('Ctrl') || has('Mod') ? 'Ctrl' : '', has('Alt') ? 'Alt' : '', has('Shift') ? 'Shift' : '', has('Cmd') ? 'Meta' : '', label]
    .filter(Boolean)
    .join('+');
}
