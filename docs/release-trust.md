# Release trust

Alera release builds are expected to be trusted before they are published publicly. The release workflow builds the desktop bundle for each platform, signs or packages the platform artifact, emits a signed schema v2 update manifest, and uploads both GitHub Release assets and R2 update indexes.

## Platform signing is conditional

Platform code-signing (macOS Developer ID, Windows Authenticode) runs only when its credentials are configured as repository secrets. When they are absent the release job logs a warning and ships an unsigned platform artifact instead of failing. This is independent of update-manifest signing: the Ed25519 manifest below is always signed, so update integrity holds even for unsigned platform bundles. Configuring the relevant secrets re-enables signing automatically with no workflow change.

## macOS

Production macOS artifacts should contain a Developer ID signed and notarized `Alera.app`. When the `APPLE_*` credentials are present, the release job signs the bundled Rust sidecar under `Contents/Resources/alera/`, signs the app bundle with hardened runtime, submits it to Apple notarization, staples the ticket, and verifies the result with `codesign`, `stapler`, and `spctl`. While Apple credentials are not configured, the macOS bundle ships unsigned and users must allow it through Gatekeeper (right-click → Open, or `xattr -dr com.apple.quarantine`).

## Windows

Production Windows artifacts should be Authenticode signed. When the `WINDOWS_CERTIFICATE_*` credentials are present, the release job signs every executable payload in the bundle, including the Rust sidecar under `resources/alera/`, and verifies each signed file with `signtool verify /pa /all`. Windows SmartScreen reputation can still take time to accrue for a new publisher or certificate even when Authenticode verification succeeds. While the certificate is not configured, the Windows bundle ships unsigned and SmartScreen reports an unknown publisher; the planned trusted path is a free SignPath Foundation certificate for this MIT-licensed project.

## Linux

Linux stable distribution uses signed package repositories rather than app self-replacement. Stable release jobs build both `.deb` and `.rpm` packages from the Linux bundle, publish an APT repository with signed `InRelease` / `Release.gpg` metadata, and publish an RPM repository with signed repository metadata. Release candidates use manual Linux tarballs and must not publish to the stable package repositories. Alera may detect a newer Linux package, but updates should be installed through the user's package manager.

## Update manifest

The public update indexes use `schemaVersion: 2` and include SHA-256 and size for each platform artifact. The manifest is signed with Ed25519 and the release build embeds the public key through `ALERA_UPDATE_MANIFEST_PUBLIC_KEY`. Stable update checks reject unsigned or tampered manifests when `ALERA_SIGNED_RELEASE=true`. GitHub artifact attestations are published through GitHub's attestation service; they are not advertised as R2 sidecar URLs unless matching sidecar files are generated and uploaded.

Stable automatic installation remains disabled unless the build is signed, the manifest public key is embedded, and the platform apply path explicitly allows the artifact type.

## Runtime sidecar archive

Remote-host bootstrap uses a separate signed `runtime-archive.json` or `runtime-archive-rc.json` asset published on the GitHub Release. It lists the standalone `alera-runtime-<version>-<platform>-<arch>.tar.gz` sidecar tarballs with SHA-256 and size metadata for macOS, Windows, and Linux on both `x64` and `arm64`. The release workflow signs and verifies this archive with the same Ed25519 key as the desktop update manifest before the draft release is published. Platform code-signing remains warning-only, but runtime archive signing is required for release bootstrap; local development can still use an explicit artifact-path override outside the trusted release path.
