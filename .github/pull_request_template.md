## Summary

Describe the user-visible change.

## Screenshots

- Add screenshots or a screen recording for any new or changed UI behavior.
- If there is no visual change, say `No visual change`.

## Testing

- [ ] `dart format --set-exit-if-changed lib test integration_test tool`
- [ ] `flutter analyze`
- [ ] `flutter test --coverage --exclude-tags golden`
- [ ] `dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 100 --worst 25`
- [ ] Golden tests, if UI changed: `flutter test --tags golden`
- [ ] Desktop E2E, if app-shell flow changed: `flutter test integration_test -d macos`
- [ ] Relevant desktop build: `flutter build macos`, `flutter build windows`, or `flutter build linux`
- [ ] Landing build, if applicable: `cd landing && bun run build`
- [ ] Added or updated tests that would catch regressions, or explained why tests were not needed

## AI Review Report

Summarize the code review run with your AI coding agent, if applicable. Include the main risks it checked, what it flagged, and what changed or was verified as a result.

Confirm that cross-platform behavior was checked for macOS, Linux, and Windows when the PR touches shortcuts, labels, paths, shell behavior, terminal behavior, release behavior, or updater behavior.

## Security Audit

Call out any input handling, command execution, path handling, auth, secrets, dependency, release signing, updater, or process execution risks reviewed.

## Notes

Call out platform-specific behavior, risks, or follow-up work.
