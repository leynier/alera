# Release trust

Alera release builds are expected to be trusted before they are published publicly. The release workflow builds the desktop bundle for each platform, signs or packages the platform artifact, emits a signed schema v2 update manifest, and uploads both GitHub Release assets and R2 update indexes.

## macOS

Production macOS artifacts must contain a Developer ID signed and notarized `Alera.app`. The release job signs the bundled Rust sidecar under `Contents/Resources/alera/`, signs the app bundle with hardened runtime, submits it to Apple notarization, staples the ticket, and verifies the result with `codesign`, `stapler`, and `spctl`.

## Windows

Production Windows artifacts must be Authenticode signed. The release job signs every executable payload in the bundle, including the Rust sidecar under `resources/alera/`, and verifies each signed file with `signtool verify /pa /all`. Windows SmartScreen reputation can still take time to accrue for a new publisher or certificate even when Authenticode verification succeeds.

## Linux

Linux stable distribution uses signed package repositories rather than app self-replacement. Stable release jobs build both `.deb` and `.rpm` packages from the Linux bundle, publish an APT repository with signed `InRelease` / `Release.gpg` metadata, and publish an RPM repository with signed repository metadata. Release candidates use manual Linux tarballs and must not publish to the stable package repositories. Alera may detect a newer Linux package, but updates should be installed through the user's package manager.

## Update manifest

The public update indexes use `schemaVersion: 2` and include SHA-256 and size for each platform artifact. The manifest is signed with Ed25519 and the release build embeds the public key through `ALERA_UPDATE_MANIFEST_PUBLIC_KEY`. Stable update checks reject unsigned or tampered manifests when `ALERA_SIGNED_RELEASE=true`. GitHub artifact attestations are published through GitHub's attestation service; they are not advertised as R2 sidecar URLs unless matching sidecar files are generated and uploaded.

Stable automatic installation remains disabled unless the build is signed, the manifest public key is embedded, and the platform apply path explicitly allows the artifact type.
