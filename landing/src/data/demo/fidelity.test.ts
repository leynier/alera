import { describe, expect, test } from 'bun:test';
import { readFileSync, readdirSync } from 'node:fs';
import landingPackage from '../../../package.json';
import coverage from '../font-coverage.json';
import { APP_COPY } from './app-copy';
import { CODICONS } from './codicons';
import { lineText, type Block } from './terminal-lines';
import * as transcripts from './transcripts';

/**
 * The demo claims to be the app, so these tests hold it to the app's source:
 * colors, icons, agent marks and quoted copy are read from the Flutter and
 * Rust code and compared with what the demo draws. When one fails, update the
 * demo in the same change as the app.
 */
const repoFile = (path: string) => new URL(`../../../../${path}`, import.meta.url);
const readRepo = (path: string) => readFileSync(repoFile(path), 'utf8');
const readLanding = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');

const kebab = (name: string) => name.replace(/([a-z0-9])([A-Z])/g, '$1-$2').replace(/([A-Za-z])(\d)/g, '$1-$2').toLowerCase();

/** `Color(0xAARRGGBB)` as CSS hex: `#rrggbb` when opaque, `#rrggbbaa` otherwise. */
function cssHex(argb: string): string {
  const alpha = argb.slice(0, 2).toLowerCase();
  const rgb = argb.slice(2).toLowerCase();
  return alpha === 'ff' ? `#${rgb}` : `#${rgb}${alpha}`;
}

function cssVariables(css: string): Map<string, string> {
  return new Map([...css.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((match) => [match[1]!, match[2]!.trim()]));
}

describe('demo tokens', () => {
  const tokens = readRepo('lib/src/app/theme/alera_tokens.dart');
  const css = cssVariables(readLanding('src/styles/demo/tokens.css'));

  test('mirror every app color', () => {
    const colors = [...tokens.matchAll(/static const Color (\w+) = Color\(0x([0-9A-Fa-f]{8})\);/g)];
    expect(colors.length).toBeGreaterThan(20);
    for (const [, name, argb] of colors) {
      expect({ name, value: css.get(`--app-${kebab(name!)}`) }).toEqual({ name, value: cssHex(argb!) });
    }
  });

  test('use the app sizes for every size they name', () => {
    const sizes = new Map(
      [...tokens.matchAll(/static const double (\w+) = ([\d.]+);/g)].map((match) => [kebab(match[1]!), Number(match[2])]),
    );
    const named = [...css].filter(([name, value]) => value.endsWith('px') && sizes.has(name.replace(/^--app-/, '')));
    expect(named.length).toBeGreaterThan(20);
    for (const [name, value] of named) {
      expect({ name, value: Number.parseFloat(value) }).toEqual({ name, value: sizes.get(name.replace(/^--app-/, ''))! });
    }
  });

  test('use the app durations', () => {
    const durations = new Map(
      [...tokens.matchAll(/static const Duration (\w+) = Duration\(milliseconds: (\d+)\);/g)].map((match) => [
        `--app-${kebab(match[1]!)}`,
        `${match[2]}ms`,
      ]),
    );
    expect(durations.size).toBeGreaterThanOrEqual(4);
    for (const [name, value] of durations) expect({ name, value: css.get(name) }).toEqual({ name, value });
    const spinner = readRepo('lib/src/features/workbench/presentation/widgets/agent_run_spinner_scope.dart');
    const period = spinner.match(/duration: const Duration\(milliseconds: (\d+)\)/)?.[1];
    expect(css.get('--app-agent-spin')).toBe(`${period}ms`);
  });
});

describe('demo icons', () => {
  test('name every Lucide role the way alera_icons.dart does', () => {
    const roles = new Map(
      [...readRepo('lib/src/design_system/icons/alera_icons.dart').matchAll(/static const IconData (\w+) = LucideIcons\.(\w+);/g)].map(
        (match) => [match[1]!, kebab(match[2]!)],
      ),
    );
    // Lucide renamed these glyphs; the Flutter package keeps the old names.
    const renamed: Record<string, string> = { home: 'house' };
    const source = readLanding('src/components/demo/primitives/app-icons.ts');
    const imports = new Map(
      [...source.matchAll(/import (\w+) from '@lucide\/astro\/icons\/([\w-]+)';/g)].map((match) => [match[1]!, match[2]!]),
    );
    const entries = [...source.matchAll(/^ {2}(\w+): (\w+),$/gm)];
    expect(entries.length).toBeGreaterThan(30);
    for (const [, role, component] of entries) {
      const expected = roles.get(role!);
      expect({ role, known: expected !== undefined }).toEqual({ role, known: true });
      expect({ role, icon: imports.get(component!) }).toEqual({ role, icon: renamed[expected!] ?? expected });
    }
  });

  test('pin the Lucide release the app bundles', () => {
    // lucide_icons_flutter 3.1.17 packages Lucide 1.33.0. When the app moves,
    // move @lucide/astro with it and add the pair here.
    const bundled: Record<string, string> = { '3.1.17': '1.33.0' };
    const lock = readRepo('pubspec.lock');
    const flutterVersion = lock.match(/ {2}lucide_icons_flutter:[\s\S]*?version: "([^"]+)"/)?.[1];
    expect(bundled[flutterVersion!]).toBe(landingPackage.dependencies['@lucide/astro']);
  });

  test('draw source control actions with the app Codicons', () => {
    const codicons = new Map(
      [...readRepo('lib/src/design_system/icons/alera_codicons.dart').matchAll(/static const IconData (\w+) = IconData\(0x([0-9a-f]+)/g)].map(
        (match) => [match[1]!, Number.parseInt(match[2]!, 16)],
      ),
    );
    expect(Object.fromEntries(codicons)).toEqual({ ...CODICONS });
  });

  test('copy agent marks byte for byte', () => {
    const marks = readdirSync(new URL('../../assets/demo/agents/', import.meta.url));
    expect(marks.length).toBeGreaterThan(0);
    for (const mark of marks) {
      const demo = readFileSync(new URL(`../../assets/demo/agents/${mark}`, import.meta.url));
      expect({ mark, same: demo.equals(readFileSync(repoFile(`assets/agents/${mark}`))) }).toEqual({ mark, same: true });
    }
  });
});

describe('demo copy', () => {
  test('quote strings the app still ships', () => {
    for (const [key, entry] of Object.entries(APP_COPY) as [string, { text: string; source: string; literal?: string }][]) {
      const needle = entry.literal ?? entry.text;
      expect({ key, found: readRepo(entry.source).includes(needle) }).toEqual({ key, found: true });
    }
  });
});

describe('demo terminals', () => {
  const blocks = Object.values(transcripts).flat() as Block[];
  const text = blocks.flatMap((block) => block.lines.map(lineText)).join('\n');

  test('only use glyphs the served JetBrains Mono subsets draw', () => {
    const mono = new Set(
      Object.entries(coverage)
        .filter(([subset]) => subset.startsWith('jetbrains-mono-'))
        .flatMap(([, codepoints]) => codepoints),
    );
    const missing = [...new Set(text)].filter((glyph) => glyph !== '\n' && !mono.has(glyph.codePointAt(0)!));
    expect(missing).toEqual([]);
  });

  test('never use an em dash', () => {
    expect(text.includes('\u2014')).toBe(false);
  });
});
