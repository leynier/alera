# acp registry provider

This crate adapts registry and local ACP launch recipes to the shared Rust provider contract through `alera-provider-acp`.

Recipe resolution, authentication, capability probing, and provider flavor behavior follow the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `packages/provider-acp-registry/src/server/adapter.ts`, `probe.ts`, `copilotAcp.ts`, and `devinAcp.ts`.

The crate preserves executable, arguments, working directory, environment, agent identity, and authentication method from each resolved recipe. It does not copy provider implementation source or bundle provider runtimes.

Known registry identities expose explicit flavor metadata for Devin, Copilot, and Mistral Vibe. The wrapper preserves native `_meta` task and stream attribution, derives child task identifiers for Copilot, and maps the Mistral retry extension and rate-limit application code to normalized warnings while retaining raw frames.

The Devin flavor installs a concrete client terminal handler before initialization and advertises the ACP terminal capability. It implements `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, and `terminal/release` through an injectable process boundary. Other registry flavors do not advertise client terminals. Filesystem capabilities remain disabled.

Client command execution requires a successfully answered command approval in the active turn. Accept-for-session requires a native `allow_always` option; declines, cancellation, malformed responses, and failed response writes never grant execution. Interrupts and completed turns clear turn grants, and closure clears session grants. Generic full-access and custom approval/sandbox mappings remain unsupported.

Devin commands with no arguments are local shell source; commands with arguments execute directly. The native boundary hydrates the login-shell environment, applies explicit request overrides last, spawns windowless process trees, drains stdout and stderr independently, and kills and reaps on kill, release, interruption, close, and drop. Internal output retains the tail with lossy UTF-8 decoding: 4 MiB by default, at most 8 MiB per terminal and 16 MiB across buffered snapshots. The `terminal/output` wire preview may be smaller because its JSON escaping, typed request ID, exit metadata, and JSON-RPC envelope must fit the configured transport frame budget; such previews set `truncated: true`. Unusable frame budgets are rejected before advertising terminals, and oversized response metadata yields an explicit bounded error. Limits are 16 live and 64 unreleased terminals, with 32 released snapshots retained for embedded tool output.

Terminal identities are checked against the native session on every operation. Embedded terminal content becomes normalized command output while retaining native raw frames and metadata. Pending wait callbacks run independently of provider event polling, so cancellation of an event read does not discard the callback response.
