#!/usr/bin/env bash
set -euo pipefail

# Fails when a release APK cannot install on a real 64-bit Android phone:
#
# - libalera_mobile_native.so without the shared C++ runtime Whisper links
#   against. Cargokit copies only the Rust cdylib by default, so Android's
#   loader rejects the library before dictation can start.
# - 64-bit ELF LOAD segments aligned below 16 KB. Android 15 16 KB page-size
#   phones refuse those APKs at install time.
# - The default `app-release.apk` embedding armeabi-v7a. ML Kit's barhopper
#   (and historically the Rust cdylib) stay 4 KB aligned on 32-bit, and a fat
#   APK that includes them fails on those same 16 KB phones even when the
#   arm64 libraries are aligned.
#
# The check lives here instead of inline in the workflow so it can be run
# against fixtures: the previous inline version looked up llvm-readelf with
# `find -type f | head`, which misses the NDK symlink and can SIGPIPE under
# `pipefail`, so the release job failed with no diagnostic.

apk_dir="${1:?apk directory is required}"

if [[ ! -d "$apk_dir" ]]; then
  echo "::error::Missing Android APK directory: $apk_dir" >&2
  exit 1
fi

resolve_readelf() {
  if command -v readelf >/dev/null 2>&1; then
    command -v readelf
    return
  fi
  if command -v llvm-readelf >/dev/null 2>&1; then
    command -v llvm-readelf
    return
  fi

  local search_roots=()
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$sdk" && -d "$sdk/ndk" ]]; then
    search_roots+=("$sdk/ndk")
  fi
  local candidate
  for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      search_roots+=("$candidate")
    fi
  done

  local root found
  for root in "${search_roots[@]}"; do
    # llvm-readelf is a symlink to llvm-readobj in the NDK, so -type f misses it.
    found="$(find "$root" \( -type f -o -type l \) -name llvm-readelf -print -quit 2>/dev/null || true)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return
    fi
  done

  echo "::error::readelf was not found. Install binutils or the Android NDK." >&2
  exit 1
}

readelf="$(resolve_readelf)"
echo "Using readelf: $readelf"

shopt -s nullglob
apks=("$apk_dir"/*-release.apk)
if (( ${#apks[@]} == 0 )); then
  echo "::error::No Android release APKs found in $apk_dir" >&2
  exit 1
fi

load_align_bytes() {
  local align="$1"
  case "$align" in
    0x*|0X*)
      printf '%d\n' "$((align))"
      ;;
    '' | *[!0-9]*)
      echo ""
      ;;
    *)
      printf '%d\n' "$align"
      ;;
  esac
}

extract_dir="$(mktemp -d)"
trap 'rm -rf "$extract_dir"' EXIT

for apk in "${apks[@]}"; do
  apk_name="$(basename "$apk")"
  echo "Verifying native dependencies in $apk_name"
  listing="$(unzip -Z1 "$apk" 'lib/*' || true)"
  if ! grep -E -q '^lib/[^/]+/libalera_mobile_native\.so$' <<<"$listing"; then
    echo "::error::$apk_name is missing lib/*/libalera_mobile_native.so" >&2
    printf '%s\n' "$listing" >&2
    exit 1
  fi
  if ! grep -E -q '^lib/[^/]+/libc\+\+_shared\.so$' <<<"$listing"; then
    echo "::error::$apk_name is missing lib/*/libc++_shared.so" >&2
    printf '%s\n' "$listing" >&2
    exit 1
  fi
  if [[ "$apk_name" == "app-release.apk" ]] && grep -E -q '^lib/armeabi-v7a/' <<<"$listing"; then
    echo "::error::$apk_name is the default APK and must not embed 32-bit libraries. A fat APK that includes 4 KB-aligned armeabi-v7a objects fails to install on 16 KB page-size phones." >&2
    printf '%s\n' "$listing" >&2
    exit 1
  fi

  apk_extract="$extract_dir/${apk_name%.apk}"
  unzip -q "$apk" 'lib/*/*.so' -d "$apk_extract"

  native_found=0
  while IFS= read -r native; do
    native_found=1
    abi="$(basename "$(dirname "$native")")"
    dynamic_section="$("$readelf" -d "$native")"
    if ! grep -Fq 'Shared library: [libc++_shared.so]' <<<"$dynamic_section"; then
      echo "::error::$apk_name lib/$abi/libalera_mobile_native.so does not declare NEEDED libc++_shared.so" >&2
      printf '%s\n' "$dynamic_section" >&2
      exit 1
    fi
    if [[ ! -f "$apk_extract/lib/$abi/libc++_shared.so" ]]; then
      echo "::error::$apk_name is missing lib/$abi/libc++_shared.so beside the native library" >&2
      exit 1
    fi
    echo "Verified $apk_name lib/$abi links against bundled libc++_shared.so"
  done < <(find "$apk_extract/lib" -name libalera_mobile_native.so -type f)

  if (( native_found == 0 )); then
    echo "::error::$apk_name listed libalera_mobile_native.so but none was extracted" >&2
    exit 1
  fi

  while IFS= read -r native; do
    abi="$(basename "$(dirname "$native")")"
    case "$abi" in
      arm64-v8a | x86_64) ;;
      *) continue ;;
    esac
    aligns="$("$readelf" -lW "$native" | awk '$1 == "LOAD" { print $NF }')"
    if [[ -z "$aligns" ]]; then
      echo "::error::$apk_name lib/$abi/$(basename "$native") has no ELF LOAD segments" >&2
      "$readelf" -lW "$native" >&2
      exit 1
    fi
    for align in $aligns; do
      bytes="$(load_align_bytes "$align")"
      if [[ -z "$bytes" || "$bytes" -lt 16384 ]]; then
        echo "::error::$apk_name lib/$abi/$(basename "$native") LOAD align $align is below 16 KB" >&2
        "$readelf" -lW "$native" >&2
        exit 1
      fi
    done
    echo "Verified $apk_name lib/$abi/$(basename "$native") is 16 KB page-aligned"
  done < <(find "$apk_extract/lib" -name '*.so' -type f)
done
