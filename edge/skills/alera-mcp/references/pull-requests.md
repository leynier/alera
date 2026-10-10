# Pull Requests

Alera works with pull requests on GitHub, merge requests on GitLab, and pull requests on Azure DevOps. It uses `gh`, `glab`, or `az` on the machine that holds the workspace. A `provider_unavailable` error means that CLI is missing or signed out there; tell the user rather than retrying. Every tool takes the `workspaceId` whose branch the pull request belongs to.

## Reading

- `get_pull_request` returns the workspace's linked pull request, or the open one for its branch. It includes state, draft, mergeability, head SHA, checks, the conversation and review threads with their ids, the merge methods allowed, and the base branches. Read it before acting on a pull request.
- `list_pull_request_summaries` gives one compact row per active workspace with a pull request, with failing check names.

## Opening

- `ship_changes` does what the app's Ship Changes button does. It stages, commits with an AI Assist message, moves work off a shared base branch, pushes, and opens a pull request with AI Assist details. With `followUpWatch` it then starts Watch and Fix. It needs AI Assist. If the call times out, the ship keeps running; read `get_pull_request` for the result instead of shipping again.
- `generate_pull_request_details` writes a title and description with AI Assist without touching the forge. After about 45 seconds it may return status `running` with an `operationId`. Call again with that `operationId` as `clientRequestId`, the same workspace, and the same base branch to wait or read the result.
- `create_pull_request` opens one from the workspace's current branch. Push the branch first.
- `link_pull_request` links an existing pull request by number or URL, and `unlink_pull_request` removes the link without changing the pull request.

## Conversation And State

- `comment_pull_request` comments, or replies with `replyToCommentId`. On GitLab and Azure DevOps also pass the `threadId` from `get_pull_request`.
- `edit_pull_request_comment` replaces the text of one of your comments, using the id, source, and threadId from `get_pull_request`.
- `set_pull_request_draft` marks it draft or ready. `close_pull_request` closes it without merging (abandon on Azure DevOps).

## Merging

`merge_pull_request` merges. Choose `method` from the `mergeMethods` in `get_pull_request`. Pass `expectedHeadSha` from the state you checked, so the merge fails if someone pushed since. Merge only when the user asked for it.

## Agents On Pull Requests

- `fix_pull_request_checks` asks an agent to fix failed checks, like the Fix Failed Checks button. `restack_pull_request` asks one to rewrite the changes into reviewable commits without pushing. Both send the prompt to a running agent (`handle`) or open a tab from a profile; `preview` returns only the prompt.
- Watch and Fix sends failing checks, merge conflicts, and unresolved review threads to an agent as they appear. `start_pull_request_watch` starts it; mode `fixAndMerge` also merges once checks pass and nothing is open. `show_pull_request_watch` shows the active watch, and `stop_pull_request_watch` stops it.

## GitHub Stacks

Stacks exist only on GitHub and need the `gh-stack` extension.

- `get_pull_request_stack` shows the stack that holds the workspace's pull request, bottom layer first.
- `create_pull_request_stack` builds a stack from local workspaces, bottom to top. It pushes each branch and opens the pull requests that are missing.
- `link_pull_request_stack` stacks existing pull requests.
- `merge_pull_request_stack` merges every layer at or below the workspace's pull request at once.
