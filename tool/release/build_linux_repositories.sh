#!/usr/bin/env bash
set -euo pipefail

public_dir="${1:-public}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "::error::$name is required for Linux repository signing." >&2
    exit 64
  fi
}

require_env ALERA_LINUX_GPG_PRIVATE_KEY_BASE64
require_env ALERA_LINUX_GPG_KEY_ID

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_root"
gpg_home="$(mktemp -d "${tmp_root%/}/alera-linux-gpg.XXXXXX")"
chmod 700 "$gpg_home"
printf '%s' "$ALERA_LINUX_GPG_PRIVATE_KEY_BASE64" | base64 --decode | gpg --homedir "$gpg_home" --batch --import

apt_root="$public_dir/linux/apt"
rpm_root="$public_dir/linux/rpm"
apt_pool="$apt_root/pool/main/a/alera"
apt_dist="$apt_root/dists/stable"
rpm_arch="$rpm_root/x86_64"
mkdir -p "$apt_pool" "$apt_dist/main/binary-amd64" "$rpm_arch"

find "$public_dir/updates/stable" -type f -name '*.deb' -exec cp {} "$apt_pool/" \;
find "$public_dir/updates/stable" -type f -name '*.rpm' -exec cp {} "$rpm_arch/" \;

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
