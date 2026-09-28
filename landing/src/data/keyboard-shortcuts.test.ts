import { describe, expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { KEY_DISPLAY_LABELS } from '../lib/key-chord-label';
import { SHORTCUT_GROUPS } from './keyboard-shortcuts';

const registry = readFileSync(
  new URL('../../../lib/src/features/keyboard/domain/keyboard_action_definitions.dart', import.meta.url),
  'utf8',
);

const quoted = (text: string) => [...text.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((match) => match[1]!.replace(/\\'/g, "'"));

function registryActions() {
  return registry
    .split('KeybindingDefinition(')
    .slice(1)
    .map((block) => {
      const field = (name: string) => quoted(block.match(new RegExp(`${name}:\\s*('(?:[^'\\\\]|\\\\.)*')`))?.[1] ?? '')[0];
      const uniform = block.match(/defaultBindings: \.uniform\(<String>\[(.*?)\]\)/s);
      const perPlatform = (platform: string) => quoted(block.match(new RegExp(`${platform}: <String>\\[(.*?)\\]`, 's'))?.[1] ?? '');
      const chords = uniform ? quoted(uniform[1]!) : undefined;
      return {
        group: block.match(/group: \.(\w+)/)![1]!,
        id: block.match(/id: \.(\w+)/)![1]!,
        label: field('label'),
        description: field('description'),
        bindings: chords
          ? { macos: chords, windows: chords, linux: chords }
          : { macos: perPlatform('macos'), windows: perPlatform('windows'), linux: perPlatform('linux') },
        inTerminal: /allowInTerminal: true/.test(block),
      };
    });
}

describe('keyboard shortcuts docs data', () => {
  test('match the app registry action for action, in order', () => {
    const documented = SHORTCUT_GROUPS.flatMap((group) => group.actions.map((action) => ({ group: group.id, ...action })));
    const actions = registryActions();
    expect(actions.length).toBeGreaterThan(30);
    const inGroupOrder = SHORTCUT_GROUPS.flatMap((group) => actions.filter((action) => action.group === group.id));
    expect<unknown>(inGroupOrder).toEqual(documented);
  });

  test('only use keys the chord formatter can print', () => {
    for (const group of SHORTCUT_GROUPS) {
      for (const action of group.actions) {
        for (const chord of Object.values(action.bindings).flat()) {
          const key = chord.split('+').at(-1)!;
          expect({ chord, printable: /^([A-Z0-9]|F\d{1,2})$/.test(key) || key in KEY_DISPLAY_LABELS }).toEqual({ chord, printable: true });
        }
      }
    }
  });

  test('are the only Mod chords the docs pages cite', () => {
    const bound = new Set(SHORTCUT_GROUPS.flatMap((group) => group.actions.flatMap((action) => Object.values(action.bindings).flat())));
    const docs = new URL('../content/docs/', import.meta.url);
    const cited = readdirSync(docs)
      .filter((file) => file.endsWith('.mdx'))
      .flatMap((file) => [...readFileSync(new URL(file, docs), 'utf8').matchAll(/`(Mod\+[A-Za-z0-9+]+)`/g)].map((match) => ({ file, chord: match[1]! })));
    expect(cited.length).toBeGreaterThan(5);
    expect(cited.filter(({ chord }) => !bound.has(chord))).toEqual([]);
  });
});
