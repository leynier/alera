import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { formatChord, KEY_DISPLAY_LABELS } from './key-chord-label';

describe('key chord labels', () => {
  test('print macOS chords as glyphs in the order the app uses', () => {
    expect(formatChord('Mod+Shift+N', 'macos')).toBe('⇧⌘N');
    expect(formatChord('Mod+Alt+ArrowUp', 'macos')).toBe('⌥⌘↑');
    expect(formatChord('Ctrl+Tab', 'macos')).toBe('⌃Tab');
    expect(formatChord('Mod+Comma', 'macos')).toBe('⌘,');
  });

  test('print Windows and Linux chords with Ctrl for Mod', () => {
    expect(formatChord('Mod+Shift+BracketRight', 'windows')).toBe('Ctrl+Shift+]');
    expect(formatChord('Alt+ArrowLeft', 'linux')).toBe('Alt+←');
    expect(formatChord('Ctrl+Shift+Tab', 'windows')).toBe('Ctrl+Shift+Tab');
    expect(formatChord('Mod+Escape', 'linux')).toBe('Ctrl+Esc');
  });

  test('use the display labels key_chord.dart declares', () => {
    const source = readFileSync(new URL('../../../lib/src/features/keyboard/domain/key_chord.dart', import.meta.url), 'utf8');
    const block = (name: string) => source.slice(source.indexOf(name), source.indexOf('};', source.indexOf(name)));
    const entries = (text: string) =>
      new Map([...text.matchAll(/LogicalKeyboardKey\.(\w+):\s*r?(['"])(.*?)\2,/g)].map((match) => [match[1]!, match[3]!]));
    const tokens = entries(block('_keyToToken ='));
    const labels = entries(block('_displayLabels ='));
    const expected = Object.fromEntries([...labels].map(([key, label]) => [tokens.get(key)!, label]));
    expect(KEY_DISPLAY_LABELS).toEqual(expected);
  });
});
