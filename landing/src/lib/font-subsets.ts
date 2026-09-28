/**
 * The unicode-range of each self-hosted font subset. `scripts/subset-fonts.ts`
 * cuts the files from these ranges and `src/styles/fonts.css` declares the
 * same ranges, so a page downloads only the subsets its text needs.
 */
export interface FontSubset {
  name: 'latin' | 'latin-ext' | 'symbols';
  unicodeRange: string;
}

export const FONT_SUBSETS: readonly FontSubset[] = [
  {
    name: 'latin',
    unicodeRange:
      'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD',
  },
  {
    name: 'latin-ext',
    unicodeRange:
      'U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF',
  },
  {
    // Arrows, keyboard symbols, box drawing, shapes and dingbats: the glyphs
    // terminal UIs and shortcut labels in the product demo are drawn with.
    name: 'symbols',
    unicodeRange: 'U+2190-21FF, U+2300-23FF, U+2500-25FF, U+2600-27BF',
  },
];

export function codepointsInRanges(unicodeRange: string): number[] {
  const codepoints: number[] = [];
  for (const part of unicodeRange.split(',')) {
    const [start, end] = part.trim().replace(/^U\+/i, '').split('-');
    const first = Number.parseInt(start!, 16);
    const last = end ? Number.parseInt(end, 16) : first;
    for (let codepoint = first; codepoint <= last; codepoint += 1) codepoints.push(codepoint);
  }
  return codepoints;
}
