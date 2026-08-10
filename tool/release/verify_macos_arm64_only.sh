#!/usr/bin/env bash
set -euo pipefail

# Fails when any Mach-O inside the app bundle still carries an x86_64 slice.
#
# Alera ships for Apple Silicon only: the Homebrew cask declares
# `depends_on arch: :arm64` and the release job refuses to stage the sidecar
# unless the runner is ARM64. The Xcode default is `$(ARCHS_STANDARD)` though,
# so a build setting that is dropped or overridden silently doubles every
# binary again for a machine nobody can install on. Checking the produced
# bundle is the only place that catches that, whichever setting caused it.

app="${1:?app bundle path is required}"

if [[ ! -d "$app" ]]; then
  echo "::error::Missing app bundle: $app" >&2
  exit 1
fi

# One `file` invocation over every regular file: a universal binary reports all
# of its architectures on a single line, so a plain x86_64 Mach-O and a fat one
# both match.
offenders="$(
  find "$app" -type f -print0 |
    xargs -0 file |
    grep 'Mach-O' |
    grep 'x86_64' || true
)"

if [[ -n "$offenders" ]]; then
  echo "::error::$app contains x86_64 Mach-O binaries; Alera ships arm64 only." >&2
  echo "$offenders" >&2
  exit 1
fi

echo "Verified $app contains no x86_64 Mach-O binaries."
