/**
 * Builds the self-hosted woff2 subsets in public/fonts from the variable
 * fonts the desktop app ships (../assets/fonts), so the site renders the same
 * font versions as the app. Each subset keeps every variation axis, so one
 * file per subset covers all weights.
 *
 * Run with `bun run fonts:subset` after updating ../assets/fonts. The
 * generated coverage manifest lets tests check that every glyph the product
 * demo types is actually in a served file.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Blob, Face } from 'harfbuzzjs';
import subsetFont from 'subset-font';
import { CODICONS } from '../src/data/demo/codicons';
import { FONT_SUBSETS, codepointsInRanges } from '../src/lib/font-subsets';

const root = new URL('../', import.meta.url);
// Inter's optical-size axis is pinned to its default (14): the app never sets
// it, so every size renders the text cut, and dropping the axis halves the
// files. Weight stays variable. Hinting is dropped as browsers rasterize
// these outlines well without it.
const sources = {
  inter: { path: fileURLToPath(new URL('../assets/fonts/Inter-Variable.ttf', root)), pin: { opsz: 14 } },
  'jetbrains-mono': { path: fileURLToPath(new URL('../assets/fonts/JetBrainsMono-Variable.ttf', root)), pin: undefined },
} as const;

const coverage: Record<string, number[]> = {};

for (const [family, source] of Object.entries(sources)) {
  const font = readFileSync(source.path);
  const available = new Set(new Face(new Blob(font), 0).collectUnicodes());

  for (const subset of FONT_SUBSETS) {
    const codepoints = codepointsInRanges(subset.unicodeRange).filter((codepoint) => available.has(codepoint));
    const text = String.fromCodePoint(...codepoints);
    const woff2 = await subsetFont(font, text, {
      targetFormat: 'woff2',
      noHinting: true,
      variationAxes: source.pin,
    });
    const name = `${family}-${subset.name}`;
    writeFileSync(fileURLToPath(new URL(`public/fonts/${name}.woff2`, root)), woff2);
    coverage[name] = codepoints;
    console.log(`${name}.woff2: ${codepoints.length} glyphs, ${woff2.length} bytes`);
  }
}

writeFileSync(
  fileURLToPath(new URL('src/data/font-coverage.json', root)),
  `${JSON.stringify(coverage)}\n`,
);

// The demo's source-control icons come from the same Codicons font the app
// bundles, cut down to the glyphs `AleraCodicons` names.
const codicons = await subsetFont(
  readFileSync(fileURLToPath(new URL('../assets/fonts/VSCodeCodicons-0.0.46-24.ttf', root))),
  String.fromCodePoint(...Object.values(CODICONS)),
  { targetFormat: 'woff2', noHinting: true },
);
writeFileSync(fileURLToPath(new URL('public/demo/fonts/alera-codicons.woff2', root)), codicons);
console.log(`alera-codicons.woff2: ${Object.keys(CODICONS).length} glyphs, ${codicons.length} bytes`);
