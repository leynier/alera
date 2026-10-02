import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fetchJson,
  fetchReleaseByTag,
  inspectPinnedReleases,
  inspectStableUpdateChannel,
  readPinnedReleases,
} from './release-gate.mjs';

/**
 * Vercel ignoreCommand semantics are inverted from a normal build guard:
 * exit 0 skips the build, while exit 1 continues it. Preview and local
 * builds continue without requiring network access to GitHub.
 */
export async function runVercelIgnoreCommand({
  env = process.env,
  fetchImpl = globalThis.fetch,
  readPins = readPinnedReleases,
  logger = console,
} = {}) {
  if (env.VERCEL_ENV !== 'production') {
    logger.info?.('[release-gate] allowing non-production build');
    return 1;
  }

  try {
    const pins = await readPins();
    const [github, r2] = await Promise.all([
      inspectPinnedReleases(pins, (tag) => fetchReleaseByTag(tag, { fetchImpl })),
      inspectStableUpdateChannel(pins.desktop, {
        fetchIndex: (url) => fetchJson(url, { fetchImpl }),
        fetchDescriptor: (url) => fetchJson(url, { fetchImpl }),
      }),
    ]);
    if (github.ok && r2.ok) {
      logger.info?.('[release-gate] all pinned releases are public with their download assets');
      return 1;
    }
    for (const check of github.checks) {
      if (!check.ok) logger.error?.(`[release-gate] ${check.channel} ${check.tag}: ${check.reasons.join('; ')}`);
    }
    if (!r2.ok) logger.error?.(`[release-gate] stable R2 update channel: ${r2.reasons.join('; ')}`);
    logger.error?.('[release-gate] skipping production build until every pinned release is ready');
    return 0;
  } catch (error) {
    logger.error?.(
      `[release-gate] skipping production build because release validation failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    return 0;
  }
}

const invokedPath = process.argv[1] && resolve(process.argv[1]);
if (invokedPath === fileURLToPath(import.meta.url)) {
  process.exitCode = await runVercelIgnoreCommand();
}
