import { fileURLToPath } from 'node:url';
// Astro closes its config module runner before build:done, so load this eagerly.
import * as pagefind from 'pagefind';

// Builds the Pagefind index for /docs inside `astro:build:done`, so the index
// exists whether the host runs `astro build` directly (Vercel) or through
// `bun run build`. Only docs pages are indexed: marketing and blog copy would
// crowd out the reference answers people search the docs for.
export function docsSearchIndex() {
  return {
    name: 'alera-docs-search-index',
    hooks: {
      'astro:build:done': async ({ dir, logger }) => {
        try {
          const { index, errors: createErrors } = await pagefind.createIndex({});
          if (!index) {
            throw new Error(`docs search index could not start: ${createErrors.join('; ')}`);
          }

          const siteDir = fileURLToPath(dir);
          const { page_count: pageCount, errors } = await index.addDirectory({
            path: siteDir,
            glob: 'docs/**/*.html',
          });
          if (errors.length > 0 || pageCount === 0) {
            throw new Error(`docs search index failed (${pageCount} pages): ${errors.join('; ')}`);
          }

          const written = await index.writeFiles({
            outputPath: fileURLToPath(new URL('pagefind/', dir)),
          });
          if (written.errors.length > 0) {
            throw new Error(`docs search index could not be written: ${written.errors.join('; ')}`);
          }

          logger.info(`indexed ${pageCount} docs pages`);
        } finally {
          await pagefind.close();
        }
      },
    },
  };
}
