import { describe, expect, test } from 'bun:test';
import { detectInstallPlatform } from './install-platform';

const detect = (userAgent: string, extra: { userAgentDataPlatform?: string; maxTouchPoints?: number } = {}) =>
  detectInstallPlatform({ userAgent, maxTouchPoints: extra.maxTouchPoints ?? 0, userAgentDataPlatform: extra.userAgentDataPlatform });

describe('detectInstallPlatform', () => {
  test('recognizes desktop platforms from the user agent', () => {
    expect(detect('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15')).toBe('macos');
    expect(detect('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')).toBe('windows');
    expect(detect('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36')).toBe('linux');
  });

  test('prefers client hints when the browser provides them', () => {
    expect(detect('Mozilla/5.0', { userAgentDataPlatform: 'Windows' })).toBe('windows');
  });

  test('tells phones and tablets apart from desktops', () => {
    expect(detect('Mozilla/5.0 (Linux; Android 15; Pixel 7a) AppleWebKit/537.36')).toBe('android');
    expect(detect('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)')).toBe('ios');
    expect(detect('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)', { maxTouchPoints: 5 })).toBe('ios');
  });

  test('admits when it cannot tell', () => {
    expect(detect('curl/8.5.0')).toBeNull();
  });
});
