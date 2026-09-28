import { describe, expect, test } from 'bun:test';
import { readFileSync, readdirSync } from 'node:fs';
import landingPackage from '../../../package.json';
import coverage from '../font-coverage.json';
import { APP_COPY } from './app-copy';
import { CODICONS } from './codicons';
import { macKeys, SHORTCUTS } from './shortcuts';
import { lineText, type Block } from './terminal-lines';
import * as transcripts from './transcripts';

/**
 * The demo claims to be the app, so these tests hold it to the app's source:
 * colors, icons, agent marks and quoted copy are read from the Flutter and
 * Rust code and compared with what the demo draws. When one fails, update the
 * demo in the same change as the app.
 */
// Every app file read here is recorded, so the last test can check that the
// fidelity workflow runs when any of them changes.
const appFilesRead = new Set<string>();
const repoFile = (path: string) => {
  appFilesRead.add(path);
  return new URL(`../../../../${path}`, import.meta.url);
};
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

describe('demo terminal theme', () => {
  const css = cssVariables(readLanding('src/styles/demo/terminal.css'));

  test('paint every Alera Dark role with the token the app uses', () => {
    const catalog = readRepo('lib/src/features/settings/domain/terminal_theme_catalog.dart');
    const theme = catalog.slice(catalog.indexOf('const TerminalThemeEntry _aleraTheme'));
    const roles = [...theme.slice(0, theme.indexOf(');\n')).matchAll(/(\w+): AleraTokens\.(\w+),/g)].filter(
      ([, role]) => !role!.startsWith('searchHit'),
    );
    expect(roles.length).toBe(20);
    for (const [, role, token] of roles) {
      // The app sets every bright color to its normal one, so the demo names each once.
      const name = `--term-${kebab(role!.replace(/^bright(?!Black)(\w)/, (_, first: string) => first.toLowerCase()))}`;
      expect({ role, value: css.get(name) }).toEqual({ role, value: `var(--app-${kebab(token!)})` });
    }
  });

  test('use the default terminal font size, line height and padding', () => {
    const settings = readRepo('lib/src/features/settings/domain/alera_settings.dart');
    expect(css.get('--term-font-size')).toBe(`${settings.match(/fontSize: (\d+),/)?.[1]}px`);
    expect(css.get('--term-line-height')).toBe(settings.match(/lineHeight: ([\d.]+),/)?.[1]);
    expect(settings).toContain('this.paddingX = AleraTokens.space12');
    expect(css.get('--term-padding')).toBe('12px');
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
    const renamed: Record<string, string> = { home: 'house', history: 'rotate-ccw-clock' };
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

  test('name every phone icon the way the mobile registry does', () => {
    const roles = new Map(
      [...readRepo('mobile/lib/src/design_system/icons/alera_icons.dart').matchAll(/static const IconData (\w+) = LucideIcons\.(\w+);/g)].map(
        (match) => [match[1]!, kebab(match[2]!)],
      ),
    );
    const source = readLanding('src/components/demo/primitives/mobile-icons.ts');
    const imports = new Map(
      [...source.matchAll(/import (\w+) from '@lucide\/astro\/icons\/([\w-]+)';/g)].map((match) => [match[1]!, match[2]!]),
    );
    const entries = [...source.matchAll(/^ {2}(\w+): (\w+),$/gm)];
    expect(entries.length).toBeGreaterThan(10);
    for (const [, role, component] of entries) {
      expect({ role, icon: imports.get(component!) }).toEqual({ role, icon: roles.get(role!) });
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

  test('draw the sidebar brand with the app logo', () => {
    const demo = readFileSync(new URL('../../../public/demo/alera-logo-white.png', import.meta.url));
    expect(demo.equals(readFileSync(repoFile('assets/logo/alera-logo-white.png')))).toBe(true);
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
  const blocks = Object.values(transcripts).filter(Array.isArray).flat() as Block[];
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

describe('demo shortcuts', () => {
  test('press the macOS defaults the keyboard registry declares', () => {
    const definitions = readRepo('lib/src/features/keyboard/domain/keyboard_action_definitions.dart');
    for (const shortcut of Object.values(SHORTCUTS)) {
      const start = definitions.indexOf(`label: '${shortcut.label}',`);
      expect({ label: shortcut.label, found: start >= 0 }).toEqual({ label: shortcut.label, found: true });
      const definition = definitions.slice(start, definitions.indexOf('KeybindingDefinition(', start));
      const macos = definition.match(/macos: <String>\['([^']+)'\]/)?.[1] ?? definition.match(/\.uniform\(<String>\['([^']+)'\]\)/)?.[1];
      expect({ label: shortcut.label, chord: macos }).toEqual({ label: shortcut.label, chord: shortcut.chord });
      expect(macKeys(shortcut.chord)).toBe(shortcut.keys);
    }
  });
});

// Keep this block last: bun runs a file's tests in order, so every read above has happened.
describe('demo fidelity workflow', () => {
  test('runs when any app file these tests read changes', () => {
    const workflow = readRepo('.github/workflows/landing-fidelity.yml');
    const watched = [...workflow.matchAll(/^\s+- '([^']+)'$/gm)].map((match) => new Bun.Glob(match[1]!));
    expect(watched.length).toBeGreaterThan(5);
    const unwatched = [...appFilesRead].filter((path) => !path.startsWith('.github/') && !watched.some((glob) => glob.match(path)));
    expect(unwatched).toEqual([]);
  });
});
