import { describe, expect, test } from 'bun:test';
import releases from './releases.json';
import {
  ANDROID_URL,
  BREW_COMMAND,
  CHOCO_COMMAND,
  INSTALL_SCRIPT_COMMAND,
  LINUX_KEY_FINGERPRINT,
  MACOS_ASSET,
  MACOS_URL,
  SCOOP_COMMAND,
  WINDOWS_ASSET,
} from './install-channels';

describe('install channels', () => {
  test('links the exact assets of the pinned releases', () => {
    expect(MACOS_ASSET).toBe(`alera-${releases.desktop.version}-macos.tar.gz`);
    expect(WINDOWS_ASSET).toBe(`alera-${releases.desktop.version}-windows.tar.gz`);
    expect(MACOS_URL).toBe(
      `https://github.com/leynier/alera/releases/download/${releases.desktop.tag}/${MACOS_ASSET}`,
    );
    expect(ANDROID_URL).toEndWith(`/${releases.mobile.tag}/alera-${releases.mobile.version}-android.apk`);
  });

  test('spells the package manager commands the release cut publishes', () => {
    expect(BREW_COMMAND).toContain('brew install --cask alera');
    expect(SCOOP_COMMAND).toContain('scoop install leynier/alera');
    expect(CHOCO_COMMAND).toBe('choco install alera');
    expect(INSTALL_SCRIPT_COMMAND).toBe('curl -fsSL https://alera.build/install.sh | sh');
  });

  test('quotes the same key fingerprint the installer pins', async () => {
    const script = await Bun.file(new URL('../../public/install.sh', import.meta.url)).text();
    expect(script).toContain(LINUX_KEY_FINGERPRINT);
  });
});
