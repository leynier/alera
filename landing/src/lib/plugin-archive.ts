import { createHash } from 'node:crypto';
import { zipSync, type Zippable } from 'fflate';

/** Build-time packaging for the two new distributions; existing archives keep their builders. */
export function buildPluginArchive(files: Record<string, Uint8Array>, folder: string, archive: string) {
  if (!/^[a-z0-9-]+$/.test(folder)) throw new Error('Unsafe plugin folder');
  const entries: Zippable = {};
  for (const path of Object.keys(files).sort()) {
    if (!/^[a-zA-Z0-9_ .\/-]+$/.test(path) || path.split('/').some((part) => !part || part === '.' || part === '..')) throw new Error(`Unsafe plugin path: ${path}`);
    entries[`${folder}/${path}`] = [files[path]!, { mtime: new Date(2026, 0, 1), os: 3, attrs: (0o100644 << 16) >>> 0 }];
  }
  const bytes = zipSync(entries, { level: 9 });
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return { files, bytes, sha256, checksum: `${sha256}  ${archive}\n` };
}
