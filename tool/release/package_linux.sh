#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:?bundle directory is required}"
output_dir="${2:?output directory is required}"
release_version="${3:?release version is required}"
artifact_version="${4:?artifact version is required}"
build_number="${5:?build number is required}"

if [[ ! -d "$bundle_dir" ]]; then
  echo "::error::Missing Linux bundle directory: $bundle_dir" >&2
  exit 1
fi
mkdir -p "$output_dir"
package_version="${artifact_version}"
package_release="${build_number}"
deb_version="${package_version}-${package_release}"
rpm_release="${package_release}"
if [[ "$release_version" == "$artifact_version"-rc.* ]]; then
  prerelease="${release_version#"$artifact_version"-}"
  deb_version="${package_version}~${prerelease}-${package_release}"
  rpm_release="0.${prerelease}.${package_release}"
fi
arch_deb="amd64"
arch_rpm="x86_64"
maintainer="${ALERA_LINUX_PACKAGE_MAINTAINER:-Alera Release Engineering <dev@alera.build>}"
description="Alera desktop agentic development environment."

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

install_payload() {
  local root="$1"
  mkdir -p "$root/opt/alera" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons/hicolor/256x256/apps"
  cp -R "$bundle_dir/." "$root/opt/alera/"
  ln -s /opt/alera/alera "$root/usr/bin/alera"
  if [[ -f assets/logo/alera-logo-desktop.png ]]; then
    cp assets/logo/alera-logo-desktop.png "$root/usr/share/icons/hicolor/256x256/apps/alera.png"
  fi
  cat >"$root/usr/share/applications/dev.leynier.alera.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Alera
Comment=Alera desktop agentic development environment
Exec=/opt/alera/alera
Icon=alera
StartupWMClass=dev.leynier.alera
Terminal=false
Categories=Development;
DESKTOP
}

deb_root="$stage/deb"
install_payload "$deb_root"
mkdir -p "$deb_root/DEBIAN"
installed_size="$(du -sk "$deb_root/opt/alera" | awk '{print $1}')"
# The dependency lists below are hand written, so they can only stay honest if
# every entry is one `ldd` over the bundle resolves. The tray/AppIndicator
# path links `libayatana-appindicator3`, so that runtime package belongs here.
#
# These stay declared rather than copied into the payload, which is not the
# same tradeoff for each of them:
#
#   libsecret-1-0, libsqlite3-0  First-class Depends now that WebKit no longer
#     pulls them in. Shipping our own would put a second copy under the same
#     SONAME into the process.
#   libjson-glib-1.0-0  Not reachable by dropping a .so into lib/ as things
#     stand: only `alera` carries RUNPATH `$ORIGIN/lib`, while the plugins that
#     actually need this keep the build tree's RUNPATH, so the loader never
#     searches lib/ for it. Bundling it means fixing that first.
#   libgtk-3-0  Never bundle. GTK loads theme, GIO, pixbuf and input method
#     modules from the system that are built against the system GTK, so a
#     second one breaks IME.
cat >"$deb_root/DEBIAN/control" <<DEB
Package: alera
Version: ${deb_version}
Section: devel
Priority: optional
Architecture: ${arch_deb}
Maintainer: ${maintainer}
Installed-Size: ${installed_size}
Depends: libgtk-3-0, libjson-glib-1.0-0, libsecret-1-0, libsqlite3-0, libssl3, libvulkan1, libayatana-appindicator3-1
Description: ${description}
DEB
dpkg-deb --build "$deb_root" "$output_dir/alera-${release_version}-linux.deb"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "::error::rpmbuild is required to produce the Linux RPM package." >&2
  exit 1
fi

rpm_top="$stage/rpmbuild"
mkdir -p "$rpm_top/BUILD" "$rpm_top/BUILDROOT" "$rpm_top/RPMS" "$rpm_top/SOURCES" "$rpm_top/SPECS" "$rpm_top/SRPMS"
tar_root="$stage/alera-${package_version}"
install_payload "$tar_root"
tar -C "$stage" -czf "$rpm_top/SOURCES/alera-${package_version}.tar.gz" "alera-${package_version}"
cat >"$rpm_top/SPECS/alera.spec" <<RPM
Name: alera
Version: ${package_version}
Release: ${rpm_release}%{?dist}
Summary: ${description}
License: Proprietary
BuildArch: ${arch_rpm}

Source0: %{name}-%{version}.tar.gz
Requires: gtk3
Requires: json-glib
Requires: libsecret
Requires: sqlite
Requires: openssl-libs
Requires: vulkan-loader
Requires: libayatana-appindicator-gtk3

%description
${description}

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}
cp -a . %{buildroot}/

%files
/opt/alera
/usr/bin/alera
/usr/share/applications/dev.leynier.alera.desktop
/usr/share/icons/hicolor/256x256/apps/alera.png
RPM
rpmbuild --define "_topdir $rpm_top" -bb "$rpm_top/SPECS/alera.spec"
cp "$rpm_top/RPMS/$arch_rpm/"*.rpm "$output_dir/alera-${release_version}-linux.rpm"
