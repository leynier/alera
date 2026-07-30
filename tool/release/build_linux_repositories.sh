#!/usr/bin/env bash
set -euo pipefail

public_dir="${1:-public}"
release_assets_dir="${2:-release-assets}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "::error::$name is required for Linux repository signing." >&2
    exit 64
  fi
}

if [[ ! -d "$release_assets_dir" ]]; then
  echo "::error::Missing release assets directory: $release_assets_dir" >&2
  exit 66
fi

mapfile -t deb_packages < <(
  find "$release_assets_dir" -maxdepth 1 -type f -name 'alera-*-linux.deb' -print |
    sort
)
mapfile -t rpm_packages < <(
  find "$release_assets_dir" -maxdepth 1 -type f -name 'alera-*-linux.rpm' -print |
    sort
)
if [[ "${#deb_packages[@]}" -ne 1 ]]; then
  echo "::error::Expected exactly one Linux DEB in $release_assets_dir, found ${#deb_packages[@]}." >&2
  exit 66
fi
if [[ "${#rpm_packages[@]}" -ne 1 ]]; then
  echo "::error::Expected exactly one Linux RPM in $release_assets_dir, found ${#rpm_packages[@]}." >&2
  exit 66
fi
for package in "${deb_packages[0]}" "${rpm_packages[0]}"; do
  if [[ ! -s "$package" ]]; then
    echo "::error::Linux release package is empty: $package" >&2
    exit 66
  fi
done

require_env ALERA_LINUX_GPG_PRIVATE_KEY_BASE64
require_env ALERA_LINUX_GPG_KEY_ID

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_root"
gpg_home="$(mktemp -d "${tmp_root%/}/alera-linux-gpg.XXXXXX")"
chmod 700 "$gpg_home"
trap 'rm -rf "$gpg_home"' EXIT
printf '%s' "$ALERA_LINUX_GPG_PRIVATE_KEY_BASE64" | base64 --decode | gpg --homedir "$gpg_home" --batch --import

# Reports the primary fingerprint, or nothing when gpg cannot read the key.
# The `|| true` keeps a lookup miss from tripping `set -e` inside the command
# substitution below, so the explicit checks report which key was missing
# instead of the script dying on gpg's bare exit status.
fingerprint_of() {
  gpg --homedir "$gpg_home" --batch --with-colons "$@" 2>/dev/null |
    awk -F: '/^fpr:/ { print $10; exit }' || true
}

# Users cannot add the repositories without the public half of the signing key,
# so it ships next to them. Exporting before the repositories are built fails the
# job while the manifests are still unpublished, and the fingerprint comparison
# catches a key id that does not match what actually signs below: that mismatch
# would otherwise surface as a signature failure on a user's machine against a
# repository that looks healthy from here.
keyring_file="$public_dir/linux/alera-archive-keyring.asc"
signing_fingerprint="$(fingerprint_of --fingerprint "$ALERA_LINUX_GPG_KEY_ID")"
if [[ -z "$signing_fingerprint" ]]; then
  echo "::error::Could not resolve a fingerprint for $ALERA_LINUX_GPG_KEY_ID." >&2
  exit 65
fi

mkdir -p "$public_dir/linux"
gpg --homedir "$gpg_home" --batch --yes --armor \
  --export "$ALERA_LINUX_GPG_KEY_ID" >"$keyring_file"
if [[ ! -s "$keyring_file" ]]; then
  echo "::error::Exported an empty public keyring for $ALERA_LINUX_GPG_KEY_ID." >&2
  exit 65
fi

exported_fingerprint="$(fingerprint_of --show-keys "$keyring_file")"
if [[ "$exported_fingerprint" != "$signing_fingerprint" ]]; then
  echo "::error::Exported keyring fingerprint $exported_fingerprint does not match signing key $signing_fingerprint." >&2
  exit 65
fi

apt_root="$public_dir/linux/apt"
rpm_root="$public_dir/linux/rpm"
apt_pool="$apt_root/pool/main/a/alera"
apt_dist="$apt_root/dists/stable"
rpm_arch="$rpm_root/x86_64"
mkdir -p "$apt_pool" "$apt_dist/main/binary-amd64" "$rpm_arch"

cp "${deb_packages[0]}" "$apt_pool/"
cp "${rpm_packages[0]}" "$rpm_arch/"

if ! command -v apt-ftparchive >/dev/null 2>&1; then
  echo "::error::apt-ftparchive is required to build the APT repository." >&2
  exit 1
fi
if ! command -v createrepo_c >/dev/null 2>&1; then
  echo "::error::createrepo_c is required to build the RPM repository." >&2
  exit 1
fi

(
  cd "$apt_root"
  apt-ftparchive packages pool/main/a/alera >dists/stable/main/binary-amd64/Packages
  if [[ ! -s dists/stable/main/binary-amd64/Packages ]]; then
    echo "::error::apt-ftparchive produced an empty Packages index." >&2
    exit 1
  fi
  gzip -fk dists/stable/main/binary-amd64/Packages
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=Alera \
    -o APT::FTPArchive::Release::Label=Alera \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures=amd64 \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable >dists/stable/Release
)
gpg --homedir "$gpg_home" --batch --yes --local-user "$ALERA_LINUX_GPG_KEY_ID" \
  --clearsign --digest-algo SHA256 --output "$apt_dist/InRelease" "$apt_dist/Release"
gpg --homedir "$gpg_home" --batch --yes --local-user "$ALERA_LINUX_GPG_KEY_ID" \
  --detach-sign --armor --digest-algo SHA256 --output "$apt_dist/Release.gpg" "$apt_dist/Release"

createrepo_c "$rpm_arch"
gpg --homedir "$gpg_home" --batch --yes --local-user "$ALERA_LINUX_GPG_KEY_ID" \
  --detach-sign --armor --output "$rpm_arch/repodata/repomd.xml.asc" "$rpm_arch/repodata/repomd.xml"
