# Non-blocking submissions

## Behavior

Submitting a valid form closes it immediately. The operation continues in an app-scoped `BackgroundOperations` provider, and the existing background job host shows its progress without a modal barrier. Completion never navigates or closes the screen the user subsequently opened. Failed submissions remain visible until dismissed or reviewed through Retry; Retry reopens the saved form and does not execute another write by itself. This is in-session ownership, not a durable queue across app termination.

## Audited flows

| Surface | Flow | Behavior |
| --- | --- | --- |
| Mobile | Ship Changes | Closes on submit; retains base branch, scope, and draft choice for recovery. The runtime still owns the complete Ship pipeline. |
| Mobile | Create Pull Request | Closes on submit; retains base, title, body, and draft choice. |
| Mobile | Add, reply to, or edit PR comment | Closes on submit; retains comment text for recovery. |
| Desktop and mobile | Link or change issue | Closes on submit; retains the URL and reports metadata-fetch warnings separately from linking failures. |
| Desktop and mobile | Assign or create section, including descendants | Validates before closing; runs the write in the background and retains the selection/name for recovery. |
| Mobile | Hand Off / Hand On | Validates and confirms shared impact before closing; retries preserve the original relocation id and choices. |
| Desktop | Create or delete tags | Keeps the editor available for selecting tags; Run In Background closes it while the mutation continues, with failures retained globally. Unsaved tag selections are not applied by closing. |
| Desktop | Ship, PR actions, Source Control | Already run through panel controllers; only conflicting actions are disabled, and the workbench remains usable. |
| Desktop and mobile | Workspace creation and agent startup; desktop clone | Already use retained setup jobs and close their forms. Existing retry behavior is preserved. |
| Mobile | Terminal/composer attachments and New Workspace attachments | Navigation is not blocked by a modal barrier. Upload-dependent submission remains disabled where sending early would omit an attachment. |
| Desktop | Interactive command terminal, including privileged installation | Remains interactive because commands can request passwords or confirmation and closing terminates their process tree. It is not a detached upload. |

## Ownership and feedback

The desktop and mobile packages keep separate implementations, matching their existing setup-job architecture. Background jobs retain immutable submission inputs rather than reading disposed text controllers or widget refs. Mobile PR actions hold the runtime client while the request is pending and retain the existing per-workspace write guard. Issue, section, and relocation jobs additionally reject duplicate submissions for the same target. Section and relocation submissions hold provider subscriptions until the result has been captured. Job cards share the existing host, have bounded scrolling, and sit above mobile bottom navigation.

The queue never automatically retries a write: a transport failure can occur after the host has committed, pushed, created a section, or moved a workspace. Errors are logged and retained for explicit review. Runtime protocol versions and server mutation semantics are unchanged.

## Validation

Focused controller and widget tests cover delayed requests, route dismissal before completion, navigation while Ship runs, failure visibility, comment and Ship input recovery, duplicate suppression, section retries, and relocation identity preservation. Static analysis runs for both Flutter packages.

The focused validation passed 25 desktop tests and 53 mobile tests with Flutter 3.47.2 / Dart 3.13.2. Both packages passed `flutter analyze`. This validation uses fakes and widget tests; it does not include a live device or a real GitHub mutation.
