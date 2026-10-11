import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PLUGIN_ARCHIVE, PLUGIN_NAME } from '../src/data/plugin';
import { buildPluginBundle } from '../src/lib/plugin-bundle';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(root, process.argv[2] ?? '../build/plugin');
const bundle = buildPluginBundle(root);
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, PLUGIN_ARCHIVE), bundle.bytes);
writeFileSync(resolve(output, `${PLUGIN_ARCHIVE}.sha256`), bundle.checksum);
for (const [path, bytes] of Object.entries(bundle.files)) {
  const target = resolve(output, PLUGIN_NAME, path);
  mkdirSync(resolve(target, '..'), { recursive: true });
  writeFileSync(target, bytes);
}
console.log(`Alera plugin ${bundle.version}: ${resolve(output, PLUGIN_ARCHIVE)}`);
console.log(`SHA-256: ${bundle.sha256}`);
