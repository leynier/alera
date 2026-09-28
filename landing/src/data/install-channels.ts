import releases from './releases.json';

/**
 * Every install command, asset name and repository detail the site shows,
 * in one place: the download page, the home Install section and the docs all
 * read these. `releases.json` is rewritten by
 * tool/release/update_landing_release_links.dart inside the release commit, so
 * the asset links point at the exact files a stable cut published.
 */

export const INSTALL_SCRIPT_COMMAND = 'curl -fsSL https://alera.build/install.sh | sh';

export const LINUX_KEY_FINGERPRINT = '5DE97E7CFE234A1C5869EC54708DA940734CF23A';
export const LINUX_KEYRING_URL = 'https://updates.alera.build/linux/alera-archive-keyring.asc';

export const RELEASES_URL = 'https://github.com/leynier/alera/releases/latest';
export const MOBILE_RELEASES_URL = 'https://github.com/leynier/alera/releases?q=mobile&expanded=true';

export const assetUrl = (tag: string, file: string) =>
  `https://github.com/leynier/alera/releases/download/${tag}/${file}`;

export const MACOS_ASSET = `alera-${releases.desktop.version}-macos.tar.gz`;
export const WINDOWS_ASSET = `alera-${releases.desktop.version}-windows.tar.gz`;
export const ANDROID_ASSET = `alera-${releases.mobile.version}-android.apk`;

export const MACOS_URL = assetUrl(releases.desktop.tag, MACOS_ASSET);
export const WINDOWS_URL = assetUrl(releases.desktop.tag, WINDOWS_ASSET);
export const ANDROID_URL = assetUrl(releases.mobile.tag, ANDROID_ASSET);

export const DESKTOP_VERSION = releases.desktop.version;
export const MOBILE_VERSION = releases.mobile.version;

// The manifests are pushed by the release cut from the templates under
// packaging/, so these read exactly like what it publishes.
export const BREW_COMMAND = 'brew tap leynier/tap && brew install --cask alera';
export const SCOOP_COMMAND =
  'scoop bucket add leynier https://github.com/leynier/scoop-bucket\n' + 'scoop install leynier/alera';
export const CHOCO_COMMAND = 'choco install alera';

export const APT_SOURCE = `Types: deb
URIs: https://updates.alera.build/linux/apt
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/alera-archive-keyring.asc`;

export const RPM_REPO = `[alera]
name=Alera
baseurl=https://updates.alera.build/linux/rpm/x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-alera`;

export const REQUIREMENTS = {
  macos: 'Requires Apple Silicon and macOS 14 or newer.',
  windows: 'Requires 64-bit Windows.',
  linux: 'Requires x86_64 and Ubuntu 24.04 or newer, Debian 13 or newer, or Fedora.',
  android: 'One arm64 APK for 64-bit Android phones. Pair it with your desktop runtime after installing.',
} as const;
