# Native Helper Third-Party Notices

The native emulator helper inputs in Alera are fetched during the build from immutable versioned locations and accepted only when their SHA-256 digests match `tool/native_helpers/native_helper_assets.json`. Downloaded and derived binaries are not tracked in this repository.

## scrcpy Server 4.0

- Component: Android device server from scrcpy 4.0
- Copyright: Genymobile and the scrcpy contributors
- License: Apache License 2.0
- Source: <https://github.com/Genymobile/scrcpy/tree/v4.0>
- Release artifact: <https://github.com/Genymobile/scrcpy/releases/download/v4.0/scrcpy-server-v4.0>
- Source commit: `2322868e9e256eb5fce0b3d659ab2a409f29bae1`
- License text: `licenses/scrcpy-Apache-2.0.txt`

The server is redistributed unmodified under `resources/alera/emulator/android/scrcpy/4.0/scrcpy-server`.

## serve-sim 0.1.40

- Component: native iOS Simulator streaming helper derived from the source revision published as serve-sim 0.1.40
- Copyright: Evan Bacon and the serve-sim contributors
- License: Apache License 2.0
- Source: <https://github.com/EvanBacon/serve-sim/tree/e0d98f69f3ec932ea10903fd7c8b32647949606d>
- npm artifact: <https://registry.npmjs.org/serve-sim/-/serve-sim-0.1.40.tgz>
- Source commit: `e0d98f69f3ec932ea10903fd7c8b32647949606d`
- Source archive SHA-256: `48f443481deefd4ea2a378950a19c5d160e49c0b7cb365a40eff746777d3fe2f`
- Alera patch: `patches/serve-sim-0.1.40-loopback.patch`
- Patch SHA-256: `76319a34ed99f11676c4e8adeeb508ebae56e193b3bb647ccd3f4c76cd12d93e`
- License text: `licenses/serve-sim-Apache-2.0.txt`

Alera does not redistribute the unauditable precompiled `package/bin/serve-sim-bin` from npm. The build materializer verifies the source archive, dependency lock, patch, and patched source hashes, then builds a universal `arm64` and `x86_64` helper with the active Xcode toolchain. The patch binds the unauthenticated stream, accessibility, and control endpoints to IPv6 loopback `::1` and replaces the remote Swifter dependency with the separately hash-verified local source below. The resulting helper is installed under `resources/alera/emulator/ios/serve-sim/0.1.40/serve-sim-bin`; its toolchain-dependent SHA-256 is recorded and verified in the generated bundle manifest.

## Swifter 1.5.0

- Component: HTTP and WebSocket server statically linked into the derived serve-sim helper
- Copyright: Damian Kołakowski and the Swifter contributors
- License: BSD 3-Clause
- Source: <https://github.com/httpswift/swifter/tree/9483a5d459b45c3ffd059f7b55f9638e268632fd>
- Source commit: `9483a5d459b45c3ffd059f7b55f9638e268632fd`
- Source archive SHA-256: `e80a41ebba308359ab875925c06e38adfbd6d56d8de3a25a9d1839b6178a85da`
- License text: `licenses/swifter-BSD-3-Clause.txt`

## media_kit

- Components: `media_kit` 1.2.6, `media_kit_video` 2.0.1, and `media_kit_libs_video` 1.0.7 with the platform packages pinned in `tool/native_helpers/video_runtime_assets.json`
- Copyright: Hitesh Kumar Saini and the media_kit contributors
- License: MIT
- Source: <https://github.com/media-kit/media-kit>
- License text: `licenses/media-kit-MIT.txt`

## libmpv And FFmpeg Runtime

The macOS and Windows media_kit platform packages redistribute dynamic libmpv, FFmpeg, and codec support libraries. Alera pins the exact upstream archives and validates the Windows DLL payloads in `tool/native_helpers/video_runtime_assets.json`. The macOS package uses the `video-default` archive from `libmpv-darwin-build` v0.6.0, built with mpv `-Dgpl=false` and FFmpeg without `--enable-gpl` or `--enable-nonfree`.

- mpv license for the selected build: LGPL 2.1 or later
- FFmpeg license for the selected build: LGPL 2.1 or later
- macOS build source and dependency license matrix: <https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0>
- mpv copyright and LGPL build details: <https://github.com/mpv-player/mpv/blob/master/Copyright>
- FFmpeg license and redistribution checklist: <https://ffmpeg.org/legal.html>
- LGPL license text: `licenses/libmpv-LGPL-2.1-or-later.txt`

The macOS default build also contains dynamically linked components under ISC, FreeType, MIT, LGPL 2.1, Apache 2.0, MPL 1.1, and BSD 2-Clause licenses as documented by the pinned build source. Linux uses the distribution-provided `libmpv` and `libepoxy` packages declared by the `.deb` and RPM package metadata.
