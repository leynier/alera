# Security Policy

## Supported Versions

Alera is pre-1.0. Security fixes target the default branch and the latest published release candidate or stable release when applicable.

## Reporting A Vulnerability

Please do not open a public issue for a vulnerability.

Report security concerns through GitHub private vulnerability reporting when it is enabled for the repository. If that is unavailable, contact the maintainer privately through the GitHub profile associated with this repository.

Include:

- Affected version or commit.
- Platform: macOS, Windows, Linux, or multiple.
- Reproduction steps or proof of concept.
- Impact and any known workarounds.

## Security Expectations

Contributions that touch process execution, terminals, filesystem paths, Git operations, update installation, release signing, account identity, token issuance, push delivery, cloud infrastructure, or IPC-like boundaries must include a short security review in the pull request body.

## Cloud Service And Abuse

Do not include OAuth codes, access tokens, refresh tokens, FCM registration tokens, provider client secrets, origin tokens, notification payloads, terminal content, or private user data in an issue or vulnerability report.

Report abuse of `api.alera.build`, account restrictions, or privacy concerns to `privacy@alera.build`. Include timestamps, the affected account email or public request id, and a concise description. Never send a password or credential as proof.

The public account and push service is best effort. Security-sensitive operator procedures, including edge-token, OAuth-secret, and KMS signing-key rotation, are documented in [`docs/cloud-operations.md`](docs/cloud-operations.md).
