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

Contributions that touch process execution, terminals, filesystem paths, Git operations, update installation, release signing, or IPC-like boundaries must include a short security review in the pull request body.
