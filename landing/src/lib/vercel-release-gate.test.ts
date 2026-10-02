import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import {
  inspectPinnedReleases,
  inspectStableUpdateChannel,
  STABLE_UPDATE_INDEX_URL,
  fetchJson,
  validatePublishedRelease,
  validateStableUpdateIndex,
} from '../../scripts/release-gate.mjs';
import { runVercelIgnoreCommand } from '../../scripts/vercel-ignore-build.mjs';

const pins = {
  desktop: { tag: 'v1.2.3', version: '1.2.3' },
  mobile: { tag: 'v4.5.6-mobile', version: '4.5.6' },
};

const releases = {
  'v1.2.3': {
    tag_name: 'v1.2.3',
    draft: false,
    prerelease: false,
    published_at: '2026-10-02T12:00:00Z',
    assets: [
      { name: 'alera-1.2.3-macos.tar.gz', state: 'uploaded', size: 100 },
      { name: 'alera-1.2.3-windows.tar.gz', state: 'uploaded', size: 200 },
    ],
  },
  'v4.5.6-mobile': {
    tag_name: 'v4.5.6-mobile',
    draft: false,
    prerelease: false,
    published_at: '2026-10-02T12:00:00Z',
    assets: [{ name: 'alera-4.5.6-android.apk', state: 'uploaded', size: 300 }],
  },
};

const stableIndex = {
  schemaVersion: 3,
  appName: 'Alera',
  items: ['linux', 'macos', 'windows'].map((platform) => ({
    version: '1.2.3',
    buildNumber: 478,
    platform,
    channel: 'stable',
    release: `https://updates.alera.build/updates/stable/releases/1.2.3/${platform}/release.json`,
  })),
};

const descriptors = Object.fromEntries(
  ['linux', 'macos', 'windows'].map((platform) => [
    platform,
    {
      schemaVersion: 3,
      version: '1.2.3',
      buildNumber: 478,
      platform,
      channel: 'stable',
    },
  ]),
);

const fakeFetch = async (tag: string) => releases[tag as keyof typeof releases];
const quietLogger = { info() {}, error() {} } as unknown as Console;
const responseFor = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });

const productionFetch = async (input: string) => {
  const url = new URL(input);
  if (url.hostname === 'api.github.com') {
    return responseFor(releases[url.pathname.split('/').pop() as keyof typeof releases]);
  }
  if (url.href === STABLE_UPDATE_INDEX_URL) return responseFor(stableIndex);
  const platform = url.pathname.split('/').at(-2)!;
  return responseFor(descriptors[platform as keyof typeof descriptors]);
};

describe('Vercel release gate', () => {
  test('is wired as the production project ignore command', () => {
    const config = JSON.parse(readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8')) as {
      ignoreCommand?: string;
    };
    expect(config.ignoreCommand).toBe('node scripts/vercel-ignore-build.mjs');
  });

  test('admits a stable release with uploaded non-empty landing assets', async () => {
    const result = await inspectPinnedReleases(pins, fakeFetch);
    expect(result).toEqual({
      ok: true,
      checks: [
        { channel: 'desktop', tag: 'v1.2.3', ok: true, reasons: [], missing: [], invalidAssets: [] },
        { channel: 'mobile', tag: 'v4.5.6-mobile', ok: true, reasons: [], missing: [], invalidAssets: [] },
      ],
    });
  });

  test('rejects a draft or prerelease even when its assets are uploaded', () => {
    const draft = validatePublishedRelease('desktop', pins.desktop, { ...releases['v1.2.3'], draft: true });
    const prerelease = validatePublishedRelease('desktop', pins.desktop, { ...releases['v1.2.3'], prerelease: true });
    expect(draft.ok).toBe(false);
    expect(draft.reasons).toContain('release is a draft');
    expect(prerelease.ok).toBe(false);
    expect(prerelease.reasons).toContain('release is a prerelease');
  });

  test('rejects assets that are still uploading or empty', () => {
    const result = validatePublishedRelease('desktop', pins.desktop, {
      ...releases['v1.2.3'],
      assets: [
        { name: 'alera-1.2.3-macos.tar.gz', state: 'new', size: 100 },
        { name: 'alera-1.2.3-windows.tar.gz', state: 'uploaded', size: 0 },
      ],
    });
    expect(result.ok).toBe(false);
    expect(result.invalidAssets).toEqual(['alera-1.2.3-macos.tar.gz', 'alera-1.2.3-windows.tar.gz']);
    expect(result.reasons).toContain('invalid assets: alera-1.2.3-macos.tar.gz, alera-1.2.3-windows.tar.gz');
  });

  test('requires channel-specific tags to match their pinned versions', () => {
    const desktop = validatePublishedRelease('desktop', { ...pins.desktop, tag: 'v1.2.3-mobile' }, releases['v1.2.3']);
    const mobile = validatePublishedRelease('mobile', { ...pins.mobile, tag: 'v4.5.6' }, releases['v4.5.6-mobile']);
    expect(desktop.ok).toBe(false);
    expect(desktop.reasons).toContain('pin tag is v1.2.3-mobile, expected v1.2.3');
    expect(mobile.ok).toBe(false);
    expect(mobile.reasons).toContain('pin tag is v4.5.6, expected v4.5.6-mobile');
  });

  test('rejects a release while one required asset is missing', async () => {
    const result = await inspectPinnedReleases(pins, async (tag: string) => {
      if (tag === 'v1.2.3') return { ...releases['v1.2.3'], assets: [{ name: 'alera-1.2.3-macos.tar.gz', state: 'uploaded', size: 100 }] };
      return releases[tag as keyof typeof releases];
    });
    expect(result.ok).toBe(false);
    expect(result.checks[0]).toMatchObject({
      channel: 'desktop',
      missing: ['alera-1.2.3-windows.tar.gz'],
    });
  });

  test('accepts a stable R2 index and all matching public descriptors', async () => {
    const result = await inspectStableUpdateChannel(pins.desktop, {
      fetchIndex: async () => stableIndex,
      fetchDescriptor: async (url: string) => descriptors[new URL(url).pathname.split('/').at(-2)! as keyof typeof descriptors],
    });
    expect(result.ok).toBe(true);
    expect(result.buildNumber).toBe(478);
    expect(result.descriptors).toHaveLength(3);
  });

  test('rejects a stale R2 index before fetching guessed descriptor URLs', async () => {
    let descriptorCalls = 0;
    const result = await inspectStableUpdateChannel(pins.desktop, {
      fetchIndex: async () => ({
        ...stableIndex,
        items: stableIndex.items.map((item) => ({ ...item, version: '1.2.2' })),
      }),
      fetchDescriptor: async () => {
        descriptorCalls += 1;
        return {};
      },
    });
    expect(result.ok).toBe(false);
    expect(result.reasons).toContain('linux version is 1.2.2');
    expect(descriptorCalls).toBe(0);
  });

  test('rejects an R2 descriptor URL outside the canonical stable host and path', () => {
    const result = validateStableUpdateIndex(pins.desktop, {
      ...stableIndex,
      items: stableIndex.items.map((item, index) =>
        index === 0 ? { ...item, release: 'https://example.invalid/release.json' } : item,
      ),
    });
    expect(result.ok).toBe(false);
    expect(result.reasons).toContain('linux: release URL is not the stable descriptor for linux');
  });

  test('rejects an unavailable or mismatched R2 descriptor', async () => {
    const unavailable = await inspectStableUpdateChannel(pins.desktop, {
      fetchIndex: async () => stableIndex,
      fetchDescriptor: async (url: string) => {
        if (url.endsWith('/windows/release.json')) throw new Error('HTTP 404');
        return descriptors[new URL(url).pathname.split('/').at(-2)! as keyof typeof descriptors];
      },
    });
    expect(unavailable.ok).toBe(false);
    expect(unavailable.reasons).toContain('R2 descriptor lookup failed: HTTP 404');

    const mismatched = await inspectStableUpdateChannel(pins.desktop, {
      fetchIndex: async () => stableIndex,
      fetchDescriptor: async () => ({ ...descriptors.macos, buildNumber: 477 }),
    });
    expect(mismatched.ok).toBe(false);
    expect(mismatched.reasons).toContain('descriptor build number does not match the index');
  });

  test('fails closed when the GitHub lookup fails', async () => {
    const result = await inspectPinnedReleases(pins, async (_tag: string) => {
      throw new Error('rate limited');
    });
    expect(result.ok).toBe(false);
    expect(result.checks.every((check) => check.reasons[0]?.includes('rate limited'))).toBe(true);
  });

  test('aborts a hanging JSON body after the request deadline', async () => {
    let aborted = false;
    const fetchImpl = async (_url: string, init: { signal?: AbortSignal }) => ({
      ok: true,
      json: () =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener(
            'abort',
            () => {
              aborted = true;
              reject(new Error('body aborted'));
            },
            { once: true },
          );
        }),
    });
    await expect(
      fetchJson('https://updates.alera.build/hanging.json', {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        timeoutMs: 5,
      }),
    ).rejects.toThrow('body aborted');
    expect(aborted).toBe(true);
  });

  test('continues preview builds without contacting GitHub or R2', async () => {
    let called = false;
    const exitCode = await runVercelIgnoreCommand({
      env: { VERCEL_ENV: 'preview' },
      fetchImpl: (async () => {
        called = true;
        throw new Error('should not be called');
      }) as unknown as typeof fetch,
      logger: quietLogger,
    });
    expect(exitCode).toBe(1);
    expect(called).toBe(false);
  });

  test('continues a ready production build only after GitHub and R2 pass', async () => {
    const exitCode = await runVercelIgnoreCommand({
      env: { VERCEL_ENV: 'production' },
      readPins: async () => pins,
      fetchImpl: productionFetch as unknown as typeof fetch,
      logger: quietLogger,
    });
    expect(exitCode).toBe(1);
  });

  test('skips a pending production build and waits for the post-publication redeploy', async () => {
    const exitCode = await runVercelIgnoreCommand({
      env: { VERCEL_ENV: 'production' },
      readPins: async () => pins,
      fetchImpl: (async (input: string) => {
        const url = new URL(input);
        if (url.hostname === 'api.github.com' && url.pathname.endsWith('/v1.2.3')) {
          return responseFor({ ...releases['v1.2.3'], draft: true });
        }
        return productionFetch(input);
      }) as unknown as typeof fetch,
      logger: quietLogger,
    });
    expect(exitCode).toBe(0);
  });

  test('skips a production build when R2 is unavailable', async () => {
    const exitCode = await runVercelIgnoreCommand({
      env: { VERCEL_ENV: 'production' },
      readPins: async () => pins,
      fetchImpl: (async (input: string) => {
        if (input === STABLE_UPDATE_INDEX_URL) return responseFor({}, 503);
        return productionFetch(input);
      }) as unknown as typeof fetch,
      logger: quietLogger,
    });
    expect(exitCode).toBe(0);
  });
});
