# Events And Webhooks

## Following Work

The runtime keeps a journal of events, including:
- inbox replies and question states, agent states, and terminal exits;
- orchestration task changes, decision gates, and escalations;
- automation runs, workspace starts and lifecycle, and Watch and Fix actions.

Events carry ids and states only; read details with the matching tool.

- `wait_for_events` waits for events after a cursor and returns them with the next cursor. One wait covers every kind you filter for. Prefer it to polling each question, task, or run separately. Filter with `kinds` and `workspaceId`.
- `list_events` reads the journal without waiting. `truncated` means older events were pruned.

Keep the latest cursor and pass it as `after` on the next call. Omitting `after` reads from the oldest retained event.

Clients that support MCP Events can subscribe through the protocol instead; the events and their filters are the same.

## Webhooks

A webhook sends this runtime's events to an HTTPS endpoint as signed POST requests (Standard Webhooks) through the Alera cloud. It needs a signed-in Alera account and administrative access.

- `create_webhook` adds one and returns the signing secret once. Give the secret to the user right away; it cannot be read again.
- `list_webhooks` lists them with their last delivery. `test_webhook` sends a signed test delivery. `delete_webhook` removes one.
