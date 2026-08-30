# Run Board Projections

The desktop Run Board reads the existing Rust orchestration store. The additive `orchestrationRunBoardV1` capability enables these read-only RPCs without changing either strict protocol version. A client must authenticate over the local runtime connection; mobile clients cannot read the Board. Hosts without this capability remain usable for existing features and return an Update Required state in the Board repository. There is no fallback to the legacy per-run request loop.

## List And Attention

`orchestration.boardSnapshot` accepts optional `project_id`, `workspace_id`, `search`, `bucket`, `cursor`, and `limit` fields. Filters are bounded to 256 bytes. Search matches the displayed objective preview, project name, workspace name, and run ID, treating wildcard characters literally. The default page contains 50 runs and the maximum is 100.

Each response contains a durable `revision`, filtered `counts` for Attention/Active/History, bounded run summaries in `items`, and an optional `next_cursor`. Counts ignore the selected bucket and page so they describe the entire filtered result. Items sort by creation time and ID descending. Cursor pagination requires the same revision; after a mutation the client must refresh the first page instead of appending inconsistent pages.

Completed and stopped runs belong to History. Failed runs, pending/rejected policies, failed/stalled/blocked tasks, and pending decision gates put a nonhistorical run in Attention. Remaining runs belong to Active. This is a read projection, not a change to legacy scheduling or approval semantics. Runs whose workspace or project no longer exists remain visible without invented ownership.

Task and gate counts are aggregated independently before joining runs, so multiple gates cannot multiply task counts. No task results, dispatch credentials, profile commands, or model configuration are included in list responses.

## Detail

`orchestration.runSnapshot` accepts `run_id` and optional `after_task_id`, `revision`, and `limit`. It returns the run summary, objective (up to 16,384 characters with an explicit truncation flag), and a task page. The default is 100 tasks and the maximum is 200. Task pages sort by ID and return `next_task_id`; subsequent pages must carry the original revision. Task summaries expose their own execution workspace independently of the run owner.

List objective and task title previews contain at most 256 characters. Full task results and attempt inspection are separate, on-demand surfaces, not part of these projections.

## Consistency And Events

SQLite triggers advance the Board revision in the same transaction as run, task, dispatch, gate, workspace, or project changes. Rollbacks do not advance it. Each projection reads revision, counts, and rows in one read transaction. Reopening the runtime preserves the sequence and existing runs.

Authenticated local clients receive `orchestrationBoardChanged` after orchestration requests, coordinator passes, agent hook processing, and terminal cleanup have settled. The host suppresses repeat notifications at the same revision. Project/workspace events also invalidate the client projection. Notifications carry a revision, not task payloads or credentials.

The Dart watcher coalesces bursts through the shared runtime coalescer, serializes its initial fetch with subsequent refreshes, and releases its subscription and pending work on cancellation. Connection loss is surfaced immediately; reconnection refreshes the same subscription. Errors are visible to consumers instead of silently becoming empty lists. Retry after an error is explicit or driven by a reconnect/change event; there is no new polling timer. An in-flight response from a disconnected connection is discarded.

## Resource Bounds

SQLite queries and response serialization run outside the terminal actor, with at most two active Board reads and eight total outstanding reads. The 25-second deadline includes any queue time. This leaves capacity in the four-connection store pool for runtime writes and accommodates the list, badge, and inspector refreshing together. Excess reads receive a retryable busy error instead of forming an unbounded queue. Snapshot parsing on the Dart side is limited to the bounded page already decoded by the runtime transport.
