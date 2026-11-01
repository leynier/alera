# acp registry provider

This crate adapts registry and local ACP launch recipes to the shared Rust provider contract through `alera-provider-acp`.

Recipe resolution, authentication, capability probing, and provider flavor behavior follow the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `packages/provider-acp-registry/src/server/adapter.ts`, `probe.ts`, `copilotAcp.ts`, and `devinAcp.ts`.

The crate preserves executable, arguments, working directory, environment, agent identity, and authentication method from each resolved recipe. It does not copy provider implementation source or bundle provider runtimes.

Known registry identities expose explicit flavor metadata for Devin, Copilot, and Mistral Vibe. The wrapper preserves native `_meta` task and stream attribution, derives child task identifiers for Copilot, maps the Mistral retry extension to normalized warnings, and classifies a failed turn whose `error.code` is Mistral's rate-limit application code as `usage_limit`, whether a failed prompt RPC or an idle error reported it, while retaining raw frames.

The Devin flavor installs a concrete client terminal handler before initialization and advertises the ACP terminal capability. It implements `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, and `terminal/release` through an injectable process boundary. Other registry flavors do not advertise client terminals. Filesystem capabilities remain disabled.

Client command execution requires a successfully answered command approval in the active turn; an approval that names its tool call by id only counts when the tracked call is an `execute` or `command` call. Accept-for-session requires a native `allow_always` option; declines, cancellation, malformed responses, and failed response writes never grant execution. Interrupts and completed turns clear turn grants, and closure clears session grants. Generic full-access and custom approval/sandbox mappings remain unsupported.

Devin commands with no arguments are local shell source; commands with arguments execute directly. The native boundary hydrates the login-shell environment, applies explicit request overrides last, spawns windowless process trees, drains stdout and stderr independently, and kills and reaps on kill, release, interruption, close, and drop. Internal output retains the tail with lossy UTF-8 decoding: 4 MiB by default, at most 8 MiB per terminal and 16 MiB across buffered snapshots. The `terminal/output` wire preview may be smaller because its JSON escaping, typed request ID, exit metadata, and JSON-RPC envelope must fit the configured transport frame budget; such previews set `truncated: true`. Unusable frame budgets are rejected before advertising terminals, and oversized response metadata yields an explicit bounded error. Limits are 16 live and 64 unreleased terminals, with 32 released snapshots retained for embedded tool output.

Terminal identities are checked against the native session on every operation. Embedded terminal content becomes normalized command output while retaining native raw frames and metadata. Pending wait callbacks run independently of provider event polling, so cancellation of an event read does not discard the callback response.

# Vercel fx

Vercel's fx runs as an ACP agent through `fx acp`. Add an ACP Agent instance with executable `fx`, arguments `acp` and agent id `fx`, and run `fx login` first: without a Grok subscription login fx refuses `initialize`. The `Fx` flavor is selected by the agent id `fx`, or by a local `fx`, `fx.exe` or `fx.cmd` launched with an `acp` argument, which tells it apart from the unrelated `fx` JSON viewer. As T3 Code's `fxSessionModeForPolicy` does for Supervised, the adapter writes fx's `ask` session mode after `session/new`, `session/load` and `session/resume`. fx files both its `provider` and `model` options under the `model` category; the model goes to the option whose id is `model`.
