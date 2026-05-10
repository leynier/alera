# todo: projects and worktrees feature

Tracking checklist for `projects-and-worktrees-feature-plan.md`. Update as
items are completed so the work can be resumed in a future session.

## Phase 1 — persistence scaffolding

- [x] Add `sembast` and `path_provider` to `pubspec.yaml`.
- [x] Create `lib/src/shared/infra/storage/sembast_database.dart` exposing
      `openAleraDb()` and a Riverpod `aleraDatabaseProvider`.
- [x] Domain models in `lib/src/features/projects/domain/`:
  - [x] `project.dart` (`Project`).
  - [x] `worktree.dart` (`Worktree`).
- [x] Domain models for chats:
  - [x] `lib/src/features/projects/domain/chat_summary.dart`.
  - [x] `lib/src/features/projects/domain/chat_message.dart`.
- [x] Extend `AleraSession` / `SessionCreateRequest` with `projectId` and
      `worktreeId?` (kept optional to preserve legacy callers).

## Phase 2 — repositories and services

- [x] `ProjectRepository` interface + `SembastProjectRepository`.
- [x] `ChatRepository` interface + `SembastChatRepository` (chats +
      `chat_messages` store).
- [x] `WorktreeService` (`git worktree add/remove/list` via `ProcessRunner`,
      slug + path-hash collision avoidance).
- [x] `ProjectsService` orchestration (validates repo, persists projects).
- [x] `ProjectsController` reactive state notifier driving the sidebar.
- [x] Wire new providers in `lib/src/app/providers.dart`.

## Phase 3 — session refactor

- [x] `SessionService.createSession` accepts `projectId` / `worktreeId` and
      writes through to `ChatRepository`.
- [x] `SessionService.adoptPersistedSession`, `findSessionById`,
      `deleteSession`, and `persistMessage` exposed for the controller.
- [x] `SessionController.activateChat(...)` resumes a persisted chat.
- [x] `SessionController.activateChatStub(...)` stages a brand-new chat that
      is created lazily on first prompt.
- [x] `SessionController.dropChatLocally(...)` clears the in-memory session
      when the user deletes a chat.
- [x] User prompts persisted in `_executeInput`; assistant final answer
      persisted on `turn/completed`.

## Phase 4 — UI

- [x] `lib/src/features/projects/presentation/project_sidebar.dart`.
- [x] `lib/src/features/projects/presentation/add_project_dialog.dart`.
- [x] `lib/src/features/projects/presentation/new_chat_dialog.dart`.
- [x] `lib/src/features/projects/presentation/delete_chat_dialog.dart`.
- [x] Refactor `alera_shell_page.dart` to host the sidebar; database is gated
      via `aleraDatabaseProvider` (loading/error/data states).

## Phase 5 — verification

- [x] `flutter analyze` clean (0 issues).
- [x] `flutter test` clean (300 tests pass).
- [ ] Unit tests for `ProjectRepository`, `ChatRepository`, `WorktreeService`
      with `databaseFactoryMemory` + `FakeProcessRunner` (not yet added —
      structural scaffolding is in place; coverage tests TODO).
- [ ] Integration test: create project on temp git repo → create chat with
      worktree → delete chat (with worktree) → verify dir + branch removed.
- [x] Manual smoke on macOS (`flutter run -d macos`):
      DB opens, existing projects render in the sidebar, project expansion
      works, `New chat` opens, main-repo chat stub creates a connected composer,
      and invalid project paths surface an error toast.

## Notes / decisions in flight

- Worktrees live in `~/.alera/worktrees/<repoSlug>/<name>` where `<repoSlug>`
  is `basename + 8 hex chars` of an FNV-1a hash of the absolute repo path
  (collision avoidance for repos that share a basename).
- `1 chat = 1 worktree` (or no worktree, when running on the main repo).
- Branch name pattern: `alera/<slug>` created from the project's HEAD.
- On chat delete the user is asked whether to keep or remove the worktree +
  branch. Removing falls back to `git worktree prune` if the directory is
  already gone.
- `PreferencesStore` keeps owning settings; Sembast only owns project/chat
  domain data.
- Persisted assistant text is the concatenated `markdownText` of the final
  assistant timeline cells for the completed turn — tool-call payloads are
  not yet persisted (left for a future iteration).
- Hydration of persisted chats currently resumes the codex thread with empty
  local timeline (codex backend retains the rich state). If `thread/resume`
  fails, the app surfaces an error toast — a dedicated "history is read-only"
  banner is still TODO.

## Resume protocol

If a session is interrupted, pick the next unchecked item above and continue.
Always re-run `flutter analyze` and `flutter test` before claiming a phase
complete. Update this file as the source of truth for progress.
