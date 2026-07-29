#!/bin/sh
# Alera installer for Linux.
#
#   curl -fsSL https://alera.build/install.sh | sh
#
# Adds the signed Alera package repository for the detected distribution and
# installs the alera package with the system package manager. Alera never
# installs Linux updates itself, because a raw dpkg or rpm transaction does not
# resolve the libmpv dependency closure; going through the package manager is
# what keeps dependencies resolved. Re-running this script upgrades an existing
# installation, so it is also the update path.
#
# POSIX sh on purpose: piping to `sh` runs under dash on Debian and Ubuntu.
# Everything lives in functions with `main "$@"` on the last line, so a download
# truncated mid-transfer executes nothing instead of half an installer.

set -eu

ALERA_BASE_URL="https://updates.alera.build/linux"
ALERA_KEYRING_URL="$ALERA_BASE_URL/alera-archive-keyring.asc"
ALERA_APT_URL="$ALERA_BASE_URL/apt"
ALERA_RPM_URL="$ALERA_BASE_URL/rpm/x86_64"
ALERA_RELEASES_URL="https://github.com/leynier/alera/releases"
ALERA_SOURCE_URL="https://github.com/leynier/alera#run-from-source"
ALERA_DOCS_URL="https://alera.build/#install"

# Pinned so a compromised or misconfigured artifact host cannot swap the key the
# repository is trusted with. Piping this script to sh already means trusting
# alera.build; it must not also mean trusting whatever key updates.alera.build
# happens to serve.
ALERA_KEY_FINGERPRINT="5DE97E7CFE234A1C5869EC54708DA940734CF23A"

ALERA_APT_KEYRING_PATH="/etc/apt/keyrings/alera-archive-keyring.asc"
ALERA_APT_SOURCES_PATH="/etc/apt/sources.list.d/alera.sources"
ALERA_RPM_KEYRING_PATH="/etc/pki/rpm-gpg/RPM-GPG-KEY-alera"
ALERA_RPM_REPO_PATH="/etc/yum.repos.d/alera.repo"

# Exit codes, kept distinct so the test matrix can assert which guard fired.
ALERA_EXIT_USAGE=1
ALERA_EXIT_ARCHITECTURE=2
ALERA_EXIT_DISTRIBUTION=3
ALERA_EXIT_PRIVILEGES=4
ALERA_EXIT_KEY=5
ALERA_EXIT_TOOLING=6
ALERA_EXIT_INSTALL=7

usage() {
  cat <<EOF
Usage: install.sh [options]

Options:
  --dry-run     Print the commands that would run without changing anything.
  --repo-only   Configure the package repository but do not install Alera.
  -h, --help    Show this message.

When piping this script, pass options after --, for example:
  curl -fsSL https://alera.build/install.sh | sh -s -- --dry-run
EOF
}

die() {
  status="$1"
  shift
  printf 'alera: %s\n' "$1" >&2
  shift
  for line in "$@"; do
    printf '  %s\n' "$line" >&2
  done
  exit "$status"
}

run() {
  if [ "$dry_run" -eq 1 ]; then
    printf '+'
    for argument in "$@"; do
      printf ' %s' "$argument"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

privileged() {
  if [ -n "$sudo_prefix" ]; then
    run "$sudo_prefix" "$@"
  else
    run "$@"
  fi
}

# Writes through `install` rather than a redirect so the mode is applied as the
# file lands and so the privileged form does not need a shell wrapper.
write_system_file() {
  mode="$1"
  destination="$install_root$2"
  staged="$3"
  privileged install -d -m 0755 "$(dirname "$destination")"
  privileged install -m "$mode" "$staged" "$destination"
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --repo-only) repo_only=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "$ALERA_EXIT_USAGE" "Unknown option: $1" \
          "Run install.sh --help for usage."
        ;;
    esac
    shift
  done
}

require_supported_architecture() {
  architecture="$(uname -m)"
  case "$architecture" in
    x86_64 | amd64) ;;
    *)
      die "$ALERA_EXIT_ARCHITECTURE" \
        "Alera publishes Linux packages for x86_64 only, and this machine reports $architecture." \
        "Build from source instead: $ALERA_SOURCE_URL"
      ;;
  esac
}

# Detected by probing for the binary rather than by reading ID and ID_LIKE from
# /etc/os-release, so a derivative distribution is handled by what it actually
# ships. zypper is probed only to refuse it by name: the published RPM declares
# Fedora dependency names (mpv-libs, webkit2gtk4.1, gtk3) that openSUSE does not
# provide under those names, so configuring the repository there would end in an
# unresolvable transaction rather than a working install.
detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    package_family="deb"
    package_manager="apt-get"
  elif command -v dnf >/dev/null 2>&1; then
    package_family="rpm"
    package_manager="dnf"
  elif command -v yum >/dev/null 2>&1; then
    package_family="rpm"
    package_manager="yum"
  elif command -v zypper >/dev/null 2>&1; then
    die "$ALERA_EXIT_DISTRIBUTION" \
      "openSUSE is not supported yet." \
      "The published RPM requires Fedora package names that openSUSE does not provide." \
      "Build from source instead: $ALERA_SOURCE_URL"
  else
    die "$ALERA_EXIT_DISTRIBUTION" \
      "No supported package manager was found (looked for apt-get, dnf, and yum)." \
      "Alera publishes .deb and .rpm packages only." \
      "Download a package directly: $ALERA_RELEASES_URL" \
      "Or build from source: $ALERA_SOURCE_URL"
  fi
}

select_download_tool() {
  if command -v curl >/dev/null 2>&1; then
    download() { curl -fsSL "$1" -o "$2"; }
  elif command -v wget >/dev/null 2>&1; then
    download() { wget -qO "$2" "$1"; }
  else
    die "$ALERA_EXIT_TOOLING" \
      "Either curl or wget is required to download the repository key."
  fi
}

# Resolved after the distribution check so an unsupported machine is never
# prompted for a password before being told it is unsupported.
resolve_privileges() {
  if [ "$(id -u)" -eq 0 ]; then
    sudo_prefix=""
  elif command -v sudo >/dev/null 2>&1; then
    sudo_prefix="sudo"
  else
    die "$ALERA_EXIT_PRIVILEGES" \
      "Installing needs root and sudo is not available." \
      "Re-run this script as root."
  fi
}

install_package() {
  case "$package_manager" in
    apt-get)
      privileged apt-get update
      privileged apt-get install -y "$1"
      ;;
    dnf) privileged dnf install -y "$1" ;;
    yum) privileged yum install -y "$1" ;;
  esac
}

ensure_gpg() {
  if command -v gpg >/dev/null 2>&1; then
    return 0
  fi
  printf 'Installing gnupg to verify the repository key.\n'
  case "$package_family" in
    deb) install_package gnupg ;;
    rpm) install_package gnupg2 ;;
  esac
  if [ "$dry_run" -eq 0 ] && ! command -v gpg >/dev/null 2>&1; then
    die "$ALERA_EXIT_KEY" \
      "gnupg could not be installed, so the repository key cannot be verified."
  fi
}

# Emits one line per primary key in the file. Only the fingerprint that follows a
# `pub` record is taken: a normal key carries a signing subkey, which emits its
# own `fpr` record, so matching every `fpr` would count one key as two and would
# compare the pin against whichever record happened to come first.
# --show-keys is the modern spelling; --with-fingerprint is the fallback for gpg
# older than 2.1.23.
keyring_fingerprints() {
  for option in --show-keys --with-fingerprint; do
    found="$(gpg --batch --with-colons "$option" "$1" 2>/dev/null |
      awk -F: '/^pub:/ { primary = 1; next }
               /^fpr:/ && primary { print toupper($10); primary = 0 }' || true)"
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
}

# Signed-By trusts every key in the keyring it points at, so a keyring carrying
# an extra key is a complete bypass of the pin. Both the count and the value are
# checked for that reason.
verify_keyring() {
  fingerprints="$(keyring_fingerprints "$1")"
  count="$(printf '%s\n' "$fingerprints" | grep -c '[^[:space:]]' || true)"
  if [ "$count" != "1" ]; then
    die "$ALERA_EXIT_KEY" \
      "Expected exactly one key in the downloaded keyring but found $count." \
      "Nothing was changed. Please report this at $ALERA_RELEASES_URL"
  fi
  if [ "$fingerprints" != "$ALERA_KEY_FINGERPRINT" ]; then
    die "$ALERA_EXIT_KEY" \
      "The downloaded repository key does not match the expected fingerprint." \
      "expected: $ALERA_KEY_FINGERPRINT" \
      "received: $fingerprints" \
      "Nothing was changed. Please report this at $ALERA_RELEASES_URL"
  fi
  printf 'Repository key verified: %s\n' "$ALERA_KEY_FINGERPRINT"
}

fetch_and_verify_key() {
  keyring="$work_dir/alera-archive-keyring.asc"
  printf 'Downloading the Alera repository key.\n'
  if ! download "$ALERA_KEYRING_URL" "$keyring"; then
    die "$ALERA_EXIT_KEY" \
      "Could not download the repository key from $ALERA_KEYRING_URL."
  fi
  ensure_gpg
  if [ "$dry_run" -eq 1 ] && ! command -v gpg >/dev/null 2>&1; then
    printf 'Skipping key verification: gnupg is not installed yet.\n'
    return 0
  fi
  verify_keyring "$keyring"
}

configure_deb_repository() {
  write_system_file 0644 "$ALERA_APT_KEYRING_PATH" "$keyring"
  cat >"$work_dir/alera.sources" <<EOF
# Managed by $ALERA_DOCS_URL
Types: deb
URIs: $ALERA_APT_URL
Suites: stable
Components: main
Architectures: amd64
Signed-By: $ALERA_APT_KEYRING_PATH
EOF
  write_system_file 0644 "$ALERA_APT_SOURCES_PATH" "$work_dir/alera.sources"
}

# gpgcheck stays off because the published RPMs carry no per-package signature,
# and repo_gpgcheck is what actually secures them: the signed repomd.xml commits
# to the checksum of primary.xml, which commits to the checksum of every package.
# That is the same chain APT relies on, where a signed InRelease commits to the
# hash of Packages, which commits to the hash of each .deb. Turning gpgcheck on
# before package signing exists would make every install fail as unsigned.
configure_rpm_repository() {
  write_system_file 0644 "$ALERA_RPM_KEYRING_PATH" "$keyring"
  privileged rpm --import "$install_root$ALERA_RPM_KEYRING_PATH"
  cat >"$work_dir/alera.repo" <<EOF
# Managed by $ALERA_DOCS_URL
[alera]
name=Alera
baseurl=$ALERA_RPM_URL
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=file://$ALERA_RPM_KEYRING_PATH
EOF
  write_system_file 0644 "$ALERA_RPM_REPO_PATH" "$work_dir/alera.repo"
}

report_install_failure() {
  case "$package_family" in
    deb)
      die "$ALERA_EXIT_INSTALL" "Installing Alera failed." \
        "If libmpv2 could not be found, this release is older than Alera supports." \
        "Alera needs Ubuntu 24.04 or newer, or Debian 13 or newer."
      ;;
    rpm)
      die "$ALERA_EXIT_INSTALL" "Installing Alera failed." \
        "If mpv-libs could not be found, enable RPM Fusion first." \
        "Fedora ships mpv-libs, but RHEL, Rocky, and AlmaLinux take it from RPM Fusion."
      ;;
  esac
}

main() {
  install_root="${ALERA_INSTALL_ROOT:-}"
  dry_run=0
  repo_only=0

  parse_arguments "$@"
  require_supported_architecture
  detect_package_manager
  select_download_tool
  resolve_privileges

  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT INT TERM HUP

  fetch_and_verify_key

  printf 'Configuring the Alera %s repository.\n' "$package_family"
  case "$package_family" in
    deb) configure_deb_repository ;;
    rpm) configure_rpm_repository ;;
  esac

  if [ "$repo_only" -eq 1 ]; then
    printf 'Repository configured. Skipping installation as requested.\n'
    return 0
  fi

  printf 'Installing Alera.\n'
  if ! install_package alera; then
    report_install_failure
  fi

  cat <<EOF

Alera is installed. Launch it from your application menu or run: alera

To update later, re-run this script or use your package manager directly.
EOF
}

main "$@"
