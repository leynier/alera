import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildExperimentalPluginBundle, EXPERIMENTAL_PLUGIN_ARCHIVE, EXPERIMENTAL_PLUGIN_NAME } from '../src/lib/experimental-plugin-bundle';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(root, process.argv[2] ?? '../build/experimental-plugin');
const bundle = buildExperimentalPluginBundle(root);
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, EXPERIMENTAL_PLUGIN_ARCHIVE), bundle.bytes);
writeFileSync(resolve(output, `${EXPERIMENTAL_PLUGIN_ARCHIVE}.sha256`), bundle.checksum);
for (const [path, bytes] of Object.entries(bundle.files)) {
  const target = resolve(output, EXPERIMENTAL_PLUGIN_NAME, path);
  mkdirSync(resolve(target, '..'), { recursive: true });
  writeFileSync(target, bytes);
}
console.log(`${resolve(output, EXPERIMENTAL_PLUGIN_ARCHIVE)} (${bundle.bytes.length} bytes)`);
console.log(`SHA-256: ${bundle.sha256}`);
