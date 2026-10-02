import { readFile } from 'node:fs/promises';

export const GITHUB_RELEASES_API = 'https://api.github.com/repos/leynier/alera/releases/tags/';
export const STABLE_UPDATE_INDEX_URL = 'https://updates.alera.build/updates/stable/app-archive.json';
const STABLE_UPDATE_HOST = 'updates.alera.build';
const REQUIRED_UPDATE_PLATFORMS = Object.freeze(['linux', 'macos', 'windows']);

const RELEASE_ASSETS = Object.freeze({
  desktop: (version) => [`alera-${version}-macos.tar.gz`, `alera-${version}-windows.tar.gz`],
  mobile: (version) => [`alera-${version}-android.apk`],
});

export function expectedAssets(channel, version) {
  const assetNames = RELEASE_ASSETS[channel];
  if (!assetNames) throw new Error(`Unknown release channel: ${channel}`);
  return assetNames(version);
}

function expectedReleaseTag(channel, version) {
  return channel === 'desktop' ? `v${version}` : `v${version}-mobile`;
}

export function validatePublishedRelease(channel, pin, release) {
  const reasons = [];
  const expectedTag = expectedReleaseTag(channel, pin.version);
  if (pin.tag !== expectedTag) reasons.push(`pin tag is ${pin.tag}, expected ${expectedTag}`);
  if (release?.tag_name !== pin.tag) reasons.push(`tag is ${release?.tag_name ?? 'missing'}`);
  if (release?.draft !== false) reasons.push('release is a draft');
  if (release?.prerelease !== false) reasons.push('release is a prerelease');
  if (typeof release?.published_at !== 'string' || release.published_at.length === 0) {
    reasons.push('release has no publication timestamp');
  }

  const assets = Array.isArray(release?.assets) ? release.assets : [];
  const missing = [];
  const invalidAssets = [];
  for (const assetName of expectedAssets(channel, pin.version)) {
    const matches = assets.filter((asset) => asset?.name === assetName);
    if (matches.length === 0) {
      missing.push(assetName);
      continue;
    }
    if (!matches.some((asset) => asset?.state === 'uploaded' && Number.isInteger(asset?.size) && asset.size > 0)) {
      invalidAssets.push(assetName);
    }
  }
  if (missing.length > 0) reasons.push(`missing assets: ${missing.join(', ')}`);
  if (invalidAssets.length > 0) reasons.push(`invalid assets: ${invalidAssets.join(', ')}`);

  return {
    channel,
    tag: pin.tag,
    ok: reasons.length === 0,
    reasons,
    missing,
    invalidAssets,
  };
}

/**
 * Checks both public download channels together so a partially published cut
 * never reaches production. A failed request is recorded per channel and
 * therefore fails closed without preventing the other result from being
 * reported in the Vercel logs.
 */
export async function inspectPinnedReleases(pins, fetchRelease) {
  const channels = Object.entries(pins);
  const checks = await Promise.all(
    channels.map(async ([channel, pin]) => {
      try {
        return validatePublishedRelease(channel, pin, await fetchRelease(pin.tag));
      } catch (error) {
        return {
          channel,
          tag: pin.tag,
          ok: false,
          reasons: [`GitHub release lookup failed: ${error instanceof Error ? error.message : String(error)}`],
          missing: expectedAssets(channel, pin.version),
          invalidAssets: [],
        };
      }
    }),
  );
  return { ok: checks.length > 0 && checks.every((check) => check.ok), checks };
}

function descriptorPath(version, platform) {
  return `/updates/stable/releases/${version}/${platform}/release.json`;
}

function validateDescriptorUrl(pin, platform, value) {
  if (typeof value !== 'string' || value.trim().length === 0) return 'release URL is missing';
  try {
    const url = new URL(value);
    if (
      url.protocol !== 'https:' ||
      url.hostname !== STABLE_UPDATE_HOST ||
      url.port !== '' ||
      url.search !== '' ||
      url.hash !== '' ||
      url.pathname !== descriptorPath(pin.version, platform)
    ) {
      return `release URL is not the stable descriptor for ${platform}`;
    }
  } catch {
    return 'release URL is invalid';
  }
  return undefined;
}

export function validateStableUpdateIndex(pin, index) {
  const reasons = [];
  const descriptors = [];
  if (index?.schemaVersion !== 3) reasons.push('R2 index schemaVersion is not 3');
  if (index?.appName !== 'Alera') reasons.push('R2 index appName is not Alera');

  const rawItems = index?.items;
  if (!Array.isArray(rawItems) || rawItems.length !== REQUIRED_UPDATE_PLATFORMS.length) {
    reasons.push(`R2 index must contain ${REQUIRED_UPDATE_PLATFORMS.length} platform items`);
    return { ok: false, reasons, descriptors, buildNumber: undefined };
  }

  const seenPlatforms = new Set();
  let buildNumber;
  for (const rawItem of rawItems) {
    const platform = rawItem?.platform;
    if (!REQUIRED_UPDATE_PLATFORMS.includes(platform) || seenPlatforms.has(platform)) {
      reasons.push(`R2 index contains invalid platform ${platform ?? 'missing'}`);
      continue;
    }
    seenPlatforms.add(platform);
    if (rawItem.channel !== 'stable') reasons.push(`${platform} descriptor is not stable`);
    if (rawItem.version !== pin.version) reasons.push(`${platform} version is ${rawItem.version ?? 'missing'}`);
    if (!Number.isInteger(rawItem.buildNumber) || rawItem.buildNumber <= 0) {
      reasons.push(`${platform} build number is invalid`);
    } else if (buildNumber === undefined) {
      buildNumber = rawItem.buildNumber;
    } else if (rawItem.buildNumber !== buildNumber) {
      reasons.push(`${platform} build number does not match ${buildNumber}`);
    }

    const urlReason = validateDescriptorUrl(pin, platform, rawItem.release);
    if (urlReason) reasons.push(`${platform}: ${urlReason}`);
    else descriptors.push({ platform, buildNumber: rawItem.buildNumber, url: rawItem.release });
  }

  for (const platform of REQUIRED_UPDATE_PLATFORMS) {
    if (!seenPlatforms.has(platform)) reasons.push(`R2 index is missing ${platform}`);
  }
  return { ok: reasons.length === 0, reasons, descriptors, buildNumber };
}

export function validateStableDescriptor(pin, item, descriptor) {
  const reasons = [];
  if (descriptor?.schemaVersion !== 3) reasons.push('descriptor schemaVersion is not 3');
  if (descriptor?.channel !== 'stable') reasons.push('descriptor channel is not stable');
  if (descriptor?.version !== pin.version) reasons.push(`descriptor version is ${descriptor?.version ?? 'missing'}`);
  if (descriptor?.buildNumber !== item.buildNumber) reasons.push('descriptor build number does not match the index');
  if (descriptor?.platform !== item.platform) reasons.push('descriptor platform does not match the index');
  return { ok: reasons.length === 0, reasons };
}

export async function inspectStableUpdateChannel(pin, { fetchIndex, fetchDescriptor }) {
  try {
    const indexCheck = validateStableUpdateIndex(pin, await fetchIndex(STABLE_UPDATE_INDEX_URL));
    if (!indexCheck.ok) return { ...indexCheck, descriptors: [] };

    const descriptors = await Promise.all(
      indexCheck.descriptors.map(async (item) => {
        try {
          const check = validateStableDescriptor(pin, item, await fetchDescriptor(item.url));
          return { ...item, ...check };
        } catch (error) {
          return {
            ...item,
            ok: false,
            reasons: [`R2 descriptor lookup failed: ${error instanceof Error ? error.message : String(error)}`],
          };
        }
      }),
    );
    const reasons = descriptors.flatMap((descriptor) => descriptor.reasons);
    return { ok: reasons.length === 0, reasons, descriptors, buildNumber: indexCheck.buildNumber };
  } catch (error) {
    return {
      ok: false,
      reasons: [`R2 update channel lookup failed: ${error instanceof Error ? error.message : String(error)}`],
      descriptors: [],
      buildNumber: undefined,
    };
  }
}

export async function fetchResponse(
  url,
  { fetchImpl = globalThis.fetch, method = 'GET', headers = {}, timeoutMs = 10_000, consume } = {},
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method,
      headers,
      redirect: 'error',
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    // Keep the abort signal alive while the caller consumes the body. Native fetch
    // ties that signal to the response stream, so a stalled body is bounded too.
    return consume ? await consume(response) : response;
  } finally {
    clearTimeout(timeout);
  }
}

export async function fetchJson(url, options = {}) {
  return fetchResponse(url, { ...options, consume: (response) => response.json() });
}

export async function fetchReleaseByTag(tag, { fetchImpl = globalThis.fetch, timeoutMs = 10_000 } = {}) {
  return fetchJson(`${GITHUB_RELEASES_API}${encodeURIComponent(tag)}`, {
    fetchImpl,
    timeoutMs,
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'alera-landing-release-gate',
    },
  });
}

export async function readPinnedReleases(path = new URL('../src/data/releases.json', import.meta.url)) {
  return JSON.parse(await readFile(path, 'utf8'));
}
