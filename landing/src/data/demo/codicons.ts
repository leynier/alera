/**
 * The VS Code Codicons the desktop app draws its source-control actions with,
 * by the same names and code points as `lib/src/design_system/icons/alera_codicons.dart`.
 * `scripts/subset-fonts.ts` cuts `public/demo/fonts/alera-codicons.woff2` from
 * the app's own font file with exactly these glyphs.
 */
export const CODICONS = {
  add: 0xea60,
  sync: 0xea77,
  check: 0xeab2,
  cloudUpload: 0xeac3,
  discard: 0xeae2,
  refresh: 0xeb37,
  remove: 0xeb3b,
  repoPull: 0xeb40,
  repoPush: 0xeb41,
  gitStash: 0xec26,
  gitStashPop: 0xec28,
  gitFetch: 0xecb2,
  terminalLinux: 0xebc6,
} as const;

export type CodiconName = keyof typeof CODICONS;
