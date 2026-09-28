import { describe, expect, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import coverage from '../data/font-coverage.json';
import { FONT_SUBSETS, codepointsInRanges } from './font-subsets';

const fontsCss = readFileSync(fileURLToPath(new URL('../styles/fonts.css', import.meta.url)), 'utf8');

describe('font subsets', () => {
  test('declares every generated subset in fonts.css with the same unicode range', () => {
    for (const family of ['inter', 'jetbrains-mono']) {
      for (const subset of FONT_SUBSETS) {
        const file = `/fonts/${family}-${subset.name}.woff2`;
        expect(existsSync(fileURLToPath(new URL(`../../public${file}`, import.meta.url))), file).toBe(true);
        const face = fontsCss.split('@font-face').find((block) => block.includes(file));
        expect(face, file).toBeDefined();
        expect(face).toContain(`unicode-range: ${subset.unicodeRange};`);
      }
    }
  });

  test('expands ranges and single code points', () => {
    expect(codepointsInRanges('U+0041-0043, U+2318')).toEqual([0x41, 0x42, 0x43, 0x2318]);
  });

  test('records which glyphs each served file contains', () => {
    const mono = new Set(coverage['jetbrains-mono-symbols']);
    for (const glyph of '●❯✓✗└├│─╭╮╰╯⌘⇧⌥⏎→') {
      expect(mono.has(glyph.codePointAt(0)!), glyph).toBe(true);
    }
    expect(coverage['inter-latin'].length).toBeGreaterThan(200);
  });
});
