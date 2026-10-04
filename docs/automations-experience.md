# Automations Experience

## Implemented Behavior

| Area | Behavior |
| --- | --- |
| Authoring | Four steps on desktop and mobile: task, explicit target, schedule, and review. Save activates; Save As Draft remains available. |
| Discovery | Runtime-local catalog with project, section, and workspace entry points. Origin association is independent of execution target and follows workspace section moves. |
| Lifecycle | Active edits stay Active and apply to future runs. Pause stops scheduling while admitted runs can continue. Completed definitions support cloning, running again, and trashing. |
| Validation | Field-level prompt, schedule, target, and launchable-profile checks replace approval and policy gates. |
| Agents | The dedicated `alera-automations` skill is referenced by the base CLI skill and available through skill setup. CLI creation accepts ordinary flags or partial JSON with server defaults and an idempotency key. |
| Execution | Scheduled admission and occurrence claims commit together. Each run freezes its admitted definition revision. Pending runs remain eligible when their definition is paused. |
| Recovery | Reconcile the owner before launching. Resume a captured native conversation once, then continue with context in the preserved workspace. Persist three total launches by default, 60/120 second backoff, and the original 24-hour deadline. |
| Observation | Watch Terminal attaches read-only to a live session or retained checkpoint. It cannot write, resize, reclaim, terminate, or restart that session. Take Over explicitly stops automatic recovery. |
| Uncertain Owners | Reserve targets until process closure is proven. A timed-out run can retain its reservation; new work waits for the previous owner. A healthy SSH owner is reattached without injecting another startup command. |
| History | Preserve attempt terminals and output by default. Run Again creates a new linked run and retains the original final history. Successful later runs clear historical failure attention. |

## Runtime Boundaries

Creation does not enable login autostart or change keep-runtime settings. A runtime must be running to execute schedules. Occurrences missed while offline default to Skip; recovering an already admitted run is a separate path.

Generic terminal restoration excludes automation-owned tabs until Take Over. The automation runner alone decides whether to resume or retry them. Process identity includes a PID and start marker; Linux also persists the boot identity. A live or unverified owner is never replaced merely because its transport disappeared.

Recovery copies the original task, previous summary/error, and bounded local Git status and diff statistics into the retry prompt. It does not copy terminal output or file contents. The saved agent launch configuration and permissions remain authoritative. SSH recovery directs the agent to reconcile the preserved remote files.

The authoring and observation capabilities are additive. `createOrAttach` accepts `attachmentMode: observe`; `terminal.observe` offers the same behavior. Mobile forwards observation through `terminal.attach`. Legacy generic attachment retains its takeover semantics. `approve` remains a deprecated activation alias; policy requests return a retirement error.

Migration reactivates only technically valid definitions with unambiguous audit evidence that a removed gate stopped a previously active automation. Technical failures remain Blocked; ambiguous history, ordinary drafts, and manually paused definitions are preserved.

## Validation

- Desktop and mobile generation, formatting, static analysis, and feature/widget suites, including authoring, contextual catalog views, observation, and takeover transitions.
- Core automation tests for atomic admission, concurrent run numbering, frozen revisions, schedule cursors, persistent attempt budgets/deadlines, conservative migration, retirement, and cleanup.
- Runtime and CLI automation tests for gate removal, readiness, idempotent authoring, stale revisions/attempts, terminal retention, manual recovery while paused, final owner reservations, and linked Run Again history.
- Headless runtime integration tests, including an actual process restart that recovers into a new attempt in the same workspace, retains the deadline, observes read-only, and never replays a completed automation terminal.
- Landing token/shortcut fidelity, skill validation, formatting, whitespace, and file-length checks.

Runtime integration was executed on Linux with simulated agents. Physical computer reboot and live macOS/Windows or SSH-machine failure tests were not performed. No real scheduled provider task was needed for these checks. The UI work was delegated to the same Claude Opus Dev profile throughout.
