import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { PLUGIN_ARCHIVE, PLUGIN_CHECKSUM_URL, PLUGIN_DOWNLOAD_URL } from '../src/data/plugin';
import { buildPluginBundle } from '../src/lib/plugin-bundle';

export function pluginDownload(): AstroIntegration {
  let root: string;
  return {
    name: 'alera-plugin-download',
    hooks: {
      'astro:config:done': ({ config }) => { root = fileURLToPath(config.root); },
      'astro:build:done': ({ dir, logger }) => {
        const bundle = buildPluginBundle(root);
        const downloads = new URL('downloads/', dir);
        mkdirSync(downloads, { recursive: true });
        writeFileSync(new URL(PLUGIN_ARCHIVE, downloads), bundle.bytes);
        writeFileSync(new URL(`${PLUGIN_ARCHIVE}.sha256`, downloads), bundle.checksum);
        logger.info(`packaged Alera plugin ${bundle.version} (${bundle.bytes.length} bytes)`);
      },
      'astro:server:setup': ({ server }) => {
        server.middlewares.use((request, response, next) => {
          const path = request.url?.split('?')[0];
          if (path !== PLUGIN_DOWNLOAD_URL && path !== PLUGIN_CHECKSUM_URL) return next();
          const bundle = buildPluginBundle(root);
          const archive = path === PLUGIN_DOWNLOAD_URL;
          response.setHeader('Content-Type', archive ? 'application/zip' : 'text/plain; charset=utf-8');
          if (archive) response.setHeader('Content-Disposition', `attachment; filename="${PLUGIN_ARCHIVE}"`);
          response.end(archive ? bundle.bytes : bundle.checksum);
        });
      },
    },
  };
}
