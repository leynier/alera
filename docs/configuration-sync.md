# Configuration Sync

Configuration Sync is manual and account-scoped. Open **Settings > Configuration Sync** on desktop or mobile. Sign in first, then review the shared revision before applying or uploading. Mobile explicitly distinguishes **This Phone** from **Connected Device**; a connected runtime verifies the account inside its configuration transaction. Local features remain available without an account.

## Review, Apply And Upload

Review compares the last observed shared base, current device configuration and current cloud head. Independent edits are proposed automatically. Conflicts remain unresolved until the user chooses Local or Remote, individually or for all differences. Profiles and text actions use stable ids; order is separate. Names can be edited in the review when importing or renaming a profile would collide. Missing values on first connection are additions, not deletions.

**Apply To Device** saves the chosen result without publishing. **Apply And Upload** saves locally first and then publishes a conditional new revision. A lost response or network failure leaves an account-scoped pending operation; **Retry Pending Upload** reuses its operation id. The cloud rejects publishing against an outdated revision. Reviewing again is required after local changes invalidate a preview. Leaving without applying does not change configuration or the recorded base.

History lists the last 100 revisions. **Compare** loads an old revision into the same review flow. Applying it changes only the target; uploading it creates a new revision. There is no background synchronization and no automatic last-writer-wins resolution.

## Portable Data

Desktop includes portable application preferences, terminal appearance and interaction, editor settings, keyboard overrides, browser search engine, AI preferences, text actions and agent profiles. The allowlist is `desktopPortableFields` in `packages/alera_configuration`. Keyboard defaults remain platform-specific; explicit `Mod` bindings remain portable. The runtime owns a persistent portable desktop document so a paired phone can operate without a desktop window after the desktop has seeded its preferences once.

Phone configuration contains terminal quick keys, Codex preferences and portable dictation preferences. The most recently saved Codex preferences seed the phone's shared defaults; applying them also updates locally stored per-host preferences for subsequent use without uploading host ids. Active Codex conversations are not restarted. Desktop and phone blocks are distinct and unsupported blocks survive publishing from the other client.

Credentials, external account state, pairing secrets, workspace paths, per-host quotas, consent records, hooks installation, downloaded models and runtime lifecycle/resource budgets remain local. Custom commands, descriptions and prompts are user-authored text and can contain embedded secrets: review them before uploading. Importing a profile does not launch a process, install tools or grant OS permissions. Existing profile reference checks block destructive imports; the synchronization flow never changes automations or closes tabs to make an import succeed.

## Storage And Protocol

The pure Dart `alera_configuration` package supplies the document, three-way merge, review model and synchronization service to both Flutter apps. Merge and result validation run in an isolate. Documents use `schemaVersion: 1` and `shared`, `desktop`, `mobile` objects, with a 512 KiB maximum. Unknown format versions fail rather than falling back to defaults.

The runtime's `configurationSyncV1` capability is advertised in both its control file and mobile hello. Strict protocol versions do not change. `configuration.settings.seed/get/update` are local-client-only and integrate the portable document with existing settings. `configuration.snapshot/apply/published` are also available to authenticated paired clients, scoped to the runtime's current account. Cloud proxy requests (`configuration.cloud.head/history/revision/publish`) remain local-client-only and execute in deferred jobs, outside the terminal actor.

Runtime application checks a snapshot fingerprint and commits profiles, portable settings, previous-state backup and account-specific sync metadata in one SQLite transaction. Normal settings writes preserve opaque fields and dictionary resets remain effective. The 512 KiB synchronization limit does not restrict ordinary local settings edits or prevent removing oversized local prompts. Flutter consumes the acknowledged persistent state. Mobile repositories share a serialization lane and replay a durable application journal before reading or writing participating preferences after interruption. Phone snapshot decoding, fingerprinting and application/publication/journal serialization run in worker isolates while the preferences lane retains exclusive access through verification and persisted writes.

Cloud endpoints are `GET /v1/configuration`, `POST /v1/configuration`, `GET /v1/configuration/history` and `GET /v1/configuration/revisions/{revision}`. Reads require `configuration:read`; writes require `configuration:write`. Publishing takes `operationId`, `expectedRevision`, `document`, `deviceName`, and `summary`. It locks the account head, checks idempotency before concurrency, and appends one revision. Retention removes older revision bodies beyond 100; a retry whose revision has expired is rejected by its stale expected revision rather than publishing again. Account deletion cascades to configuration heads and history. The configuration routes allow 1 MiB request envelopes while the document itself remains limited to 512 KiB.

Cloud configuration uses service protection, not end-to-end encryption. HTTPS protects transport; the backend and its storage provider can read saved configuration. Configuration bodies, commands and prompts must not enter service logs or push payloads.

Configuration routes share per-account, database-backed fixed one-minute windows across service replicas: 120 reads and 20 publication attempts. A full bucket returns HTTP 429 with `configuration_rate_limited`; retries remain manual. Account deletion also removes these counters.

## Rollout And Validation

Deploy the append-only Cloud migration and backend before distributing clients. Existing clients ignore the additive endpoints. Desktop keeps its legacy repository path for runtimes without the capability; the synchronization screen requests an updated runtime. New scopes reach existing accounts through token refresh. No migration uploads configuration automatically.

Use package merge/service tests, runtime SQLite tests, desktop/mobile widget and repository tests, and the PostgreSQL configuration contract. The contract requires `TEST_DATABASE_URL` pointing to a disposable local database. Validate cross-platform presentation and device operation before release; unit or widget tests are not a substitute for testing actual desktop and phone builds.

Configuration bundles use account- and connection-scoped transfers with 128 KiB chunks, a 2 MiB assembled limit, at most eight retained transfers per runtime, and a five-minute expiry. Snapshot transfers retain one consistent snapshot; apply transfers validate the account and original local fingerprint again before committing. Incomplete transfers never change configuration. The relay envelope limit and strict terminal protocol versions remain unchanged.
