# GPUI review matrix

## Contract and baseline

- Goal: integral GPUI audit, fixes and Flutter parity verification in macOS debug and release. Goal created in task `019fb5f8-caf9-7da0-ae22-ce78731035f8` on 2026-08-30 UTC.
- Baseline: `5302b1491d95` plus the existing uncommitted changes in `project_config_requests.rs`, `terminal_search_refresh.rs`, the prior crash report and `todo.md`. Existing work is preserved.
- Current inventory: 32 Flutter feature directories, 366 Flutter presentation files and 180 GPUI Rust files. Historic counts and Done labels are not acceptance evidence.
- Status vocabulary: pendiente; en curso; fallo; corregido sin revalidar; validado; bloqueado; excluido.
- Each row is an independently tracked scenario. D and R are the debug and release gates. Source groups below are relative to `lib/src/features/` and `experiments/alera-gpui/src/app/` unless noted. Exact file/line provenance is refined during each code trace.
- Every evidence entry must identify client, commit/diff, build, fixture, screenshot, AX snapshot, actions, actual result, and finding ID. A backend-only test is not native UI validation. Blank evidence means not run.
- Shared prerequisites: one comparison UI per framework, native MacBook display, equal logical viewport/theme/content, actual profile/storage isolation verified before mutating fixtures. Preserve unrelated installed/development hosts.
- Fixtures: EMPTY=no projects; BASE=populated test profile; TREE=three projects and three-level workspaces; LONG=overflow lists; GIT=local repos and bare remote; TABS=multiple/nested panes; TERMINAL=bounded ANSI/Unicode streams; FILES=text/image/Markdown/Mermaid and failures; AGENTS/RUNS=bounded agents/hooks/status; FORGE=controlled service responses plus permitted live reads; AI=deterministic provider results; SETTINGS=test-only preferences; QUOTAS=provider/account responses; RUNTIME=owned host/sessions; MOBILE=disposable pairings; PERF=repeatable release workloads.

## SH: Shell and window

Flutter: shell, app_menu, app_window. GPUI: shell.rs, app_menu.rs, welcome_dashboard.rs. Fixture: EMPTY/BASE.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-001 | Welcome | Empty runtime | Open both clients with no projects | Same empty dashboard, disabled actions and keyboard order | fallo | pendiente | F-003: same empty runtime, matched native viewport; typography/empty-sidebar differences. Evidence SH-001-*-debug.png/ax.txt. Keyboard sequence pending. |
| SH-002 | Welcome | Populated runtime without active workspace | Deselect/retire current workspace | Welcome replaces workbench without selecting an unrelated workspace | pendiente | pendiente | Not run |
| SH-003 | App menu | Every native command | Open each menu; invoke reversible commands | Labels, enabled state, action and focus match Flutter | pendiente | pendiente | Not run |
| SH-004 | Window | Native zoom and minimum size | Double-click titlebar; resize; restore | Native display, no fullscreen confusion, no clipped controls | en curso | pendiente | Titlebar zoom, native border resize, 997x646 stacked Welcome and wheel to final shortcut now pass in both clients after fixing GPUI scroll. F003-gpui-scrollfix-bottom-matched / F003-flutter-short-bottom. Restored 1302x768. Other window/view states, precision deltas and release remain pending. |
| SH-005 | Window | Activation and hide/show | Hide, restore and change focus | Pointer gestures cancel, focus and pending output recover | pendiente | pendiente | Not run |
| SH-006 | Window | Quit and relaunch | Quit UI with retained sessions; relaunch | One UI instance, expected host survival and restored layout | en curso | pendiente | GPUI Cmd+Q closes UI PID 63856, host remains alive, relaunch shows Welcome without arbitrary workspace selection; selecting Alpha restores its tabs. F-015/F-016. Flutter cold-start pair and release remain pending. |
| SH-007 | Navigation | Back/forward including removed workspace | Visit three workspaces; remove fixture from history | Valid history, no stale selection or wrong target | pendiente | pendiente | Not run |
| SH-008 | Sidebar rail | Collapse, expand, persisted resize | Toggle rail; resize; relaunch | Same geometry and width restoration | pendiente | pendiente | Not run |
| SH-009 | About | Metadata and dismissal | Open About; keyboard/outside dismissal | Correct version/build, same copy and focus return | pendiente | pendiente | Not run |
| SH-010 | Context sidebar | All tabs and collapsed rail | Visit Explorer/Search/Git/PR/Canvas; collapse and resize | Correct visibility by Git scope, no stale previous panel | pendiente | pendiente | Not run |

## DS: Design system

Flutter: design_system, settings, keyboard. GPUI: design_system.rs, icons.rs, settings_panes. Fixture: BASE/LONG.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DS-001 | Inputs | Empty, filled and invalid values | Type/select/replace/cancel; blur; submit | Label, placeholder, focus, validation and value match | pendiente | pendiente | Not run |
| DS-002 | Textareas | Multiline Unicode and selection | Paste multiline accents/emoji; select; undo/redo | No UTF range panic, newline loss or bad selection | pendiente | pendiente | Not run |
| DS-003 | Password controls | Masked and reveal states where exposed | Inspect each registered password control | No secret leakage or inaccessible reveal action | pendiente | pendiente | Not run |
| DS-004 | Dropdowns | Trigger and click-outside | Open, toggle same trigger, click outside | Arrow differentiates input, single overlay closes correctly | pendiente | pendiente | Not run |
| DS-005 | Dropdowns | Search, keyboard and disabled option | Filter list; arrows/Enter/Escape; unavailable value | Correct selection, no lost focus or enabled invalid option | pendiente | pendiente | Not run |
| DS-006 | Switch/radio/checkbox | Mouse and keyboard states | Tab/Space/Enter across each control family | State, cursor, disabled behavior and persistence agree | pendiente | pendiente | Not run |
| DS-007 | Buttons | Hover/pressed/busy/disabled | Exercise normal and split buttons | Rounded clipping, contrast, hitbox and busy feedback match | pendiente | pendiente | Not run |
| DS-008 | Icons | Catalog and actual rendered usage | Compare Lucide/Codicons/Material/provider assets and sizes | Exact intended asset, optical size, color and state | pendiente | pendiente | Not run |
| DS-009 | Tooltips | Hover entry/exit and long content | Native hover where supported; framework event test | Correct text, delay, placement and dismissal; no click substitute | pendiente | pendiente | Not run |
| DS-010 | Overlays | Nested and near viewport edges | Open nested menu/popover/dialog; Escape/outside | No clipping, click-through, duplicate IDs or focus trap | pendiente | pendiente | Not run |
| DS-011 | Toasts | Success/error, queue and expiration | Trigger multiple fixture operations | Correct icon, text, wrapping, queue and fade | pendiente | pendiente | Not run |
| DS-012 | Loaders | All loading call sites | Induce pending/slow responses; complete/cancel | Visible animation stops when work ends, no idle frame loop | pendiente | pendiente | Not run |
| DS-013 | Scrollbars | Top/middle/bottom and nested scroll | Wheel and thumb drag with long content | Thumb geometry, endpoint travel and scroll ownership agree | pendiente | pendiente | Not run |

## WS: Projects and workspaces

Flutter: projects. GPUI: project_actions.rs, workspace_actions.rs, sidebar_*. Fixture: TREE/GIT/LONG.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WS-001 | Project add | Existing local repository | Register fixture repo using UI | Correct project/root workspace and duplicate handling | en curso | pendiente | Registration passed: GPUI Alpha, Flutter Beta, both converged to 2 projects/2 roots. Duplicate handling still pending; F-005 tracks dialog visual/UX. Evidence WS-001-*. |
| WS-002 | Project add | Folder project | Register non-Git fixture folder | No inappropriate Git actions | pendiente | pendiente | Not run |
| WS-003 | Clone | Local bare remote success | Clone controlled remote using dialog | Progress, destination, project registration and cancellation agree | pendiente | pendiente | Not run |
| WS-004 | Clone | Failure/cancel/retry | Use invalid destination/remote; cancel/retry | No stuck busy state or orphan fixture registration | pendiente | pendiente | Not run |
| WS-005 | Workspace create | Manual branch and parent selectors | Create child workspace from selected source | Branch/path/parent correct and selectors keyboard accessible | pendiente | pendiente | Not run |
| WS-006 | Workspace create | Validation and duplicates | Empty/invalid/duplicate names and branches | Clear validation with no partial unintended mutation | pendiente | pendiente | Not run |
| WS-007 | Workspace prompt | Successful AI identity workflow | Use controlled agent result | Workspace/tab created once with correct identity | pendiente | pendiente | Not run |
| WS-008 | Workspace prompt | Cancel/error after creation/retry | Delay/fail identity and launch stages | No duplicate workspace; recoverable persistent error | pendiente | pendiente | Not run |
| WS-009 | Grouping | Project | Expand three-level tree and multiple projects | Counts, nesting, row geometry and state correct | pendiente | pendiente | Not run |
| WS-010 | Grouping | None | Switch to None on same fixtures | No inherited project padding or missing descendants | pendiente | pendiente | Not run |
| WS-011 | Sorting | Name/activity/custom choices | Apply every exposed ordering | Stable hierarchy and correctly ranked descendant activity | pendiente | pendiente | Not run |
| WS-012 | Filtering | Search/project/tag/active filters | Combine, clear and restore filters | Correct rows/counts; selection remains coherent | pendiente | pendiente | Not run |
| WS-013 | Pinned | Pin/unpin and repeat pinned | Toggle pins and repeat option; relaunch | Correct duplicates, ordering and persistence | pendiente | pendiente | Not run |
| WS-014 | Tags | Select/create/edit/cancel | Edit fixture workspace tags | Same visuals, tooltip content and saved/cancelled values | pendiente | pendiente | Not run |
| WS-015 | Parent | Change parent, remove parent, cycle protection | Move fixture across tree; try invalid cycle | No cycle, missing row or incorrect indentation | pendiente | pendiente | Not run |
| WS-016 | Rows | Hover, selected and long labels | Compare root/child/grandchild and truncation | Only workspace region highlights; exact inset/padding | pendiente | pendiente | Not run |
| WS-017 | Workspace actions | Rename/reveal/copy/open | Use each context action on fixture | Correct identity, target, toast and keyboard dismissal | pendiente | pendiente | Not run |
| WS-018 | Workspace lifecycle | Sleep/reopen | Sleep disposable workspace and reopen | Sessions/tabs cleaned, activity dot correct, new terminal cwd correct | pendiente | pendiente | Not run |
| WS-019 | Workspace removal | Confirmation/cancel and controlled removal | Inspect dialog; authorized fixture completion | Exact scope, no unrelated branch/file deletion | pendiente | pendiente | Not run |
| WS-020 | Project removal | Confirmation/cancel and controlled removal | Use disposable project | Dependencies visible; no orphan workspace state | pendiente | pendiente | Not run |

## AG: Sidebar agents

Flutter: agent_status, agent_profiles. GPUI: sidebar_rows.rs, agent_profile_*. Fixture: AGENTS/TREE.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AG-001 | Agent state | working/waiting/blocked/interrupted/done | Drive each controlled status | Correct icon, animation, color, ordering and tooltip | pendiente | pendiente | Not run |
| AG-002 | Agent list | Multiple and overflow | Start four fixture agents across tree | Grouping, count, overflow and navigation match | pendiente | pendiente | Not run |
| AG-003 | Agent lifecycle | Tab closed or process exits | End fixture sessions and close owning tabs | Rows disappear and workspace is not falsely active | pendiente | pendiente | Not run |
| AG-004 | Hooks | Configured agent integration | Enable fixture-scoped integration; run bounded command | Real status events arrive without changing global hook files | pendiente | pendiente | Not run |
| AG-005 | Profiles | Create and edit managed/custom profiles | Create fixture profiles for exposed adapters | Controls, preview command, validation and persistence match | pendiente | pendiente | Not run |
| AG-006 | Profiles | Reorder and stale row actions | Reorder then edit/remove targeted fixture | Stable identity, no index panic or wrong target | pendiente | pendiente | Not run |
| AG-007 | Profiles | Discovery pending/failure | Delay/fail model and persona discovery | Animation, retry and selected values remain correct | pendiente | pendiente | Not run |
| AG-008 | Profiles | Removal impact and risk confirmation | Inspect references and warnings; cancel | Blocked references respected, focus restored | pendiente | pendiente | Not run |

## TB: Workbench tabs and splits

Flutter: workbench. GPUI: tab_*, workbench_layout.rs. Fixture: TABS.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TB-001 | Tabs | Creation, selection and overflow | Create many tabs; scroll strip; select through overflow | Same geometry, ordering and active tab | pendiente | pendiente | Not run |
| TB-002 | Tab menu | All entries including Change Title | Right-click; rename; cancel; keyboard navigation | No edit button substitute; correct action target | pendiente | pendiente | Not run |
| TB-003 | Tab close | Inactive/active/last tab | Close disposable tabs in each state | Active fallback and workspace activity correct | pendiente | pendiente | Not run |
| TB-004 | Dirty tab | Close/cancel/save/discard paths | Dirty fixture editor; inspect each path | No silent data loss; correct document affected | pendiente | pendiente | Not run |
| TB-005 | Drag | Reorder within same pane | Move first/middle/last tab to indexed positions | Insertion preview and final order agree | pendiente | pendiente | Not run |
| TB-006 | Drag | Move between panes | Drop into other tab strip and body | Correct insertion/activation without duplicate tabs | pendiente | pendiente | Not run |
| TB-007 | Drag | Last tab leaves source pane | Move sole source tab into neighbor | Empty pane removed and remaining layout expands | pendiente | pendiente | Not run |
| TB-008 | Drag | Create left/right/top/bottom split | Drag tab to each directional edge | Directional preview then commit only on drop | pendiente | pendiente | Not run |
| TB-009 | Drag | Cancel/outside/Escape/window deactivation | Cancel at every stage | Layout unchanged and preview fully removed | pendiente | pendiente | Not run |
| TB-010 | Splits | Nested resize and persistence | Create nested panes; uneven ratios; relaunch | Ratios and active group survive restoration | pendiente | pendiente | Not run |
| TB-011 | Splits | Rapid repeated gestures | Repeat reorder/drop/cancel cycles | No frozen preview, white focus border or stale pointer state | pendiente | pendiente | Not run |

## TE: Terminal

Flutter: workbench, command_terminal. GPUI: terminal.rs, terminal_surface.rs, terminal_*. Fixture: TERMINAL/TABS.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TE-001 | Session | Workspace cwd and launch environment | Create terminal from root and child workspaces | Shell starts in exact workspace with expected environment | pendiente | pendiente | Not run |
| TE-002 | Session | Attach/snapshot/live output | Attach to retained session while it emits | Ordered output without duplication or missing UTF bytes | pendiente | pendiente | Not run |
| TE-003 | Session | Exit/unavailable/reconnect | Exit shell; disconnect test host; reconnect | Tab/activity cleanup and actionable recovery | pendiente | pendiente | Not run |
| TE-004 | Input | Printable/control/navigation keys | Type spaces, accents and control chords | Correct bytes and terminal-first interception | pendiente | pendiente | Not run |
| TE-005 | IME | Dead keys and composition | Use real active macOS input method | Composition commits once; 'a/acute produces expected accented text | pendiente | pendiente | Not run |
| TE-006 | Clipboard | Copy/paste/bracketed paste | Multiline paste and region copy | Exact selection, no bracket injection or lost newlines | pendiente | pendiente | Not run |
| TE-007 | Selection | Simple/word/line/reverse and scrolling | Select across styled/wide/combining cells | Copied text matches highlighted source rows | pendiente | pendiente | Not run |
| TE-008 | Search | Unicode folded matches | Search i in İstanbul and other length-changing case mappings | Valid original UTF boundaries; exact highlights | pendiente | pendiente | Not run |
| TE-009 | Search | ANSI style overlay | Search across colored/bold runs | No overlapping runs; colors retained and matches visible | pendiente | pendiente | Not run |
| TE-010 | Search | Output/resize/eviction during search | Redraw a to é; reflow; clear history | No stale ranges, panic or wrong navigation | pendiente | pendiente | Not run |
| TE-011 | Search | Close/reopen/focus and result navigation | Next/previous; close; type into terminal | Correct count and focus returned to visible surface | en curso | pendiente | Rebuilt GPUI: Cmd+F displays usable width, review-alpha finds 1/1, Close Search then typing printf executes review_focus_ok without refocusing. Evidence TE-011-gpui-before/after-*. Next/previous, Escape, switching owner and Flutter native comparison remain pending. |
| TE-012 | Cursor | Shape/blink/opacity/focus | Change settings and switch focus | Visible cursor and appropriate animation | pendiente | pendiente | Not run |
| TE-013 | Scrollback | Long retained history and scrollbar | Scroll/drag to ends; emit more output | No jumps, mismatched thumb or unwanted autoscroll | pendiente | pendiente | Not run |
| TE-014 | Links | Plain URL/OSC8/wrapped link | Inspect hover/activation on safe fixture link | Correct target and modifier policy | pendiente | pendiente | Not run |
| TE-015 | Path drop | Files with spaces and Unicode | Drop fixture path into terminal | Correct quoting without executing arbitrary input | pendiente | pendiente | Not run |
| TE-016 | Toolbar | Move and four corners | Drag handle, resize, persist position | Bounds, snapping, menu and search overlay placement agree | pendiente | pendiente | Not run |
| TE-017 | Composer | Multiline, attachments and visibility | Compose/cancel/send bounded fixture text | Focus, payload and clear behavior match | pendiente | pendiente | Not run |
| TE-018 | Pulse | Configure/arm/cancel | Use harmless fixture pulse | Correct timing, disabled/busy state and cancellation | pendiente | pendiente | Not run |
| TE-019 | Restore | Burst/backlog and resync | Replay large retained output plus concurrent data | No lost marker, duplicate rows or unsupported session state | pendiente | pendiente | Not run |
| TE-020 | Command terminal | Open/action completion/error | Run controlled support command | Correct title/cwd, lifecycle and follow-up | pendiente | pendiente | Not run |

## FS: Explorer search and editor

Flutter: workbench. GPUI: workspace_surface.rs, explorer_*, search_*, editor_*. Fixture: FILES/GIT.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FS-001 | Explorer | Empty/nested/ignored tree | Expand/collapse and toggle ignored visibility | Lazy rows, icons and controls correct | pendiente | pendiente | Not run |
| FS-002 | Explorer | New file/folder, rename and move | Mutate disposable fixture entries | Correct path, refreshed tree and open-tab identity | pendiente | pendiente | Not run |
| FS-003 | Explorer | External rename/delete and errors | Change fixture from another process | Stale item handled without panic or wrong document | pendiente | pendiente | Not run |
| FS-004 | Explorer | Source Control root | Select nested repo root; rename enclosing path | Git scope and persistence follow the selected root | pendiente | pendiente | Not run |
| FS-005 | Search | Query, grouping and navigation | Search fixture content; select results | Counts, paths, line/column and editor location correct | en curso | pendiente | F-012 corrected and matched natively: both open source docs/guide.md:3 and select needle one. GPUI evidence FS-005-gpui-after; Flutter FS-005-flutter-recheck-click. Other query/grouping variants remain pending. |
| FS-006 | Search | Regex/case/word/include/exclude/ignored | Exercise every toggle and invalid regex | Equivalent result semantics and error state | pendiente | pendiente | Not run |
| FS-007 | Replace | One/all/conflict/cancel | Replace fixture matches with changed-file conflict | Accurate preview, confirmations and safe writes | pendiente | pendiente | Not run |
| FS-008 | Editor | Load, empty, large and invalid file | Open each fixture type and delayed read | Correct loading/error and responsive UI | pendiente | pendiente | Not run |
| FS-009 | Editor | Typing, selection, undo/redo and clipboard | Edit Unicode fixture and undo | Exact buffer content and dirty state | en curso | pendiente | F018-gpui-fixed-beta-undo/redo verifies history survives workspace navigation; two undos restore baseline after synthetic multi-event typing. Unicode/clipboard/full state variants remain pending. |
| FS-010 | Editor | Save/autosave and external conflict | Edit then modify disk concurrently | No overwrite without intended conflict resolution | en curso | pendiente | Saving Beta/conflict.txt writes only Beta, not Alpha's homonymous file; baseline restored through undo/save and verified in both files. Autosave/conflict and delayed save variants remain pending (F-019). |
| FS-011 | Editor | Two panes same/different documents | Edit and save/discard from either pane | Independent documents and shared-path coherence | pendiente | pendiente | Not run |
| FS-012 | Editor | Close/reopen with pending read/save | Race file load/save against tab/workspace switch | No resurrected tabs, lost drafts or stale content | pendiente | pendiente | Not run |
| FS-013 | Editor | Normal workspace navigation and homonymous drafts | Edit A/B, return, undo/redo/save; close inactive B from Flutter and reopen | Drafts/history stay separate, save targets correct file, closed state is retired | validado | pendiente | F-018 fixed debug: Alpha/Beta conflict.txt preserve independent drafts; undo/redo survives; Beta-only save verified; closing B from Flutter preserves dirty A; reopening B has clean baseline and no retired undo history. Evidence F018-gpui-fixed-*, alpha-after-remote-beta-close, beta-reopened-no-history. In-flight save belongs to FS-012/F-019, not this normal-navigation pass. |

## PV: Preview and diffs

Flutter: workbench, reading_diff. GPUI: preview_surface.rs, markdown_preview_images.rs, git_diff_*. Fixture: FILES/GIT.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PV-001 | Markdown | Typography, lists, tables and code | Open rich fixture; copy code; toggle source | Flutter structure, icons, spacing and exact copied text | fallo | pendiente | F-009 dark paint revalidated in PV-001-gpui-after-dark versus PV-001-flutter-recheck. Text is legible; table remains full-width with different borders instead of Flutter intrinsic width. Typography and copy/source variants pending. |
| PV-002 | Markdown | Images/links/unsafe or missing resource | Use local/remote-denied/missing fixtures | Correct errors and safe resolution, no path escape | pendiente | pendiente | Not run |
| PV-003 | Mermaid | Normal/error/large diagram | Render valid and invalid diagram; zoom/pan | No clipping, hang or unrecoverable failure | pendiente | pendiente | Not run |
| PV-004 | Images | Raster/SVG/large/corrupt | Open each image fixture; zoom/pan/reset | Contained viewport and explicit decode errors | pendiente | pendiente | Not run |
| PV-005 | Diff | Working tree and commit file diff | Open added/modified/deleted/binary fixtures | Correct sides, metadata, context and open-file action | pendiente | pendiente | Not run |
| PV-006 | Preview lifecycle | Toggle/resize/close during loading | Switch tabs before delayed content completes | No stale preview, leaked asset or focus border | pendiente | pendiente | Not run |

## SC: Source Control

Flutter: workbench. GPUI: context_source_control*, context_source_history*, workspace_git.rs. Fixture: GIT.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SC-001 | Status | Clean/dirty/staged/untracked/conflict | Present each Git fixture | Correct groups/counts/icons and disabled actions | pendiente | pendiente | Not run |
| SC-002 | Views | Tree/list and grouped/unified | Switch view modes and expand directories | Stable selection and scoped row actions | pendiente | pendiente | Not run |
| SC-003 | Stage | File/directory/all and reverse | Stage/unstage controlled changes | Exact paths and refreshed index status | pendiente | pendiente | Not run |
| SC-004 | Discard | Confirm/cancel/error | Inspect and exercise disposable fixtures under safety gate | No unrelated data loss or incorrect scope | pendiente | pendiente | Not run |
| SC-005 | Commit | Message/AI/commit/amend validation | Commit locally and amend fixture history | Busy/error state and commit result correct | pendiente | pendiente | Not run |
| SC-006 | Network Git | Fetch/pull/push local remote | Use controlled bare remote and conflicting peer | Progress, failures and retry match Flutter | pendiente | pendiente | Not run |
| SC-007 | Stash | Create/pick/pop/conflict | Use multiple stashes and conflict fixture | Correct stash identity and conflict feedback | pendiente | pendiente | Not run |
| SC-008 | History | Graph/refs/incoming/outgoing/pagination | Navigate branching fixture history | Graph, selection and file diff metadata agree | pendiente | pendiente | Not run |
| SC-009 | Menus | Keyboard/outside/rounded split-button hover | Open all source menus and dismiss | No square hover bleed, invisible text or retained menu | pendiente | pendiente | Not run |
| SC-010 | Git errors | Missing repo/root/credentials/network | Induce each supported failure | Actionable nonfatal state and safe retry | pendiente | pendiente | Not run |

## PR: Pull Requests and CI

Flutter: pull_requests. GPUI: context_pull_request*, forge_*. Fixture: FORGE.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PR-001 | Composer | No PR, validation and branch picker | Fill/cancel local form; vary base/title/body | Same controls, dropdowns and validation | pendiente | pendiente | Not run |
| PR-002 | Link | Existing/invalid/closed PR | Read fixture/live safe PR reference | Correct association or actionable failure | pendiente | pendiente | Not run |
| PR-003 | Review | Metadata/checks/comments | Inspect pending/success/failure/long data | Correct icons, grouping, links and scrolling | pendiente | pendiente | Not run |
| PR-004 | Write actions | Create/update/comment/review | Exercise local service fixtures; live writes only with authorization | Correct payload/busy/error and no double submit | pendiente | pendiente | Not run |
| PR-005 | Lifecycle actions | Draft/ready/close/merge methods | Inspect confirmations; controlled backend tests | Correct target/method and protected external writes | pendiente | pendiente | Not run |
| PR-006 | Failures | Auth/offline/stale response | Delay/fail response then switch workspace | No stale PR replaces current workspace | en curso | pendiente | Unsupported local-remote state captured in both; F-010 missing GPUI header/Refresh. Other errors and late-response scenarios pending. |

## AI: AI Assist and text actions

Flutter: ai_assist, reading_diff, text_actions. GPUI: ai_assist_settings_catalog.rs, reading_diff*, text_actions_*. Fixture: AI/FILES/GIT.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AI-001 | AI Assist | All five prompt sections | Visit commit/PR/diff/workspace/speech settings | Inputs/selects initialized; values persist and search anchors work | pendiente | pendiente | Not run |
| AI-002 | Discovery | Agent/model/reasoning overrides | Switch agent/model with discovery pending/error | Valid selections, inherited values and no stale response | pendiente | pendiente | Not run |
| AI-003 | Generation | Success and streaming output | Run bounded fixture through each supported entry point | Correct result destination and single apply | pendiente | pendiente | Not run |
| AI-004 | Generation | Cancel/timeout/retry/late completion | Use deterministic delayed provider | No hidden job, duplicate workspace or replaced newer draft | pendiente | pendiente | Not run |
| AI-005 | Instructions | Unicode multiline/reset/reopen | Edit fixture instructions and restore/reset | Exact text and isolated operation settings | pendiente | pendiente | Not run |
| AI-006 | Reading Diff | Source/AI/invalid output | Run controlled diff-only result and failures | Original remains accessible; errors not destructive | pendiente | pendiente | Not run |
| AI-007 | Text Actions | Create/edit/reorder/duplicate/delete | Use disposable action definitions | Stable identity, proper overrides and list persistence | pendiente | pendiente | Not run |
| AI-008 | Text Actions | Selection execution and cancellation | Apply action to controlled selected text | Correct selected range, undo and cancellation | pendiente | pendiente | Not run |
| AI-009 | AI secrets | Credentials and generated output boundaries | Inspect logs/export/errors with fake secret markers | No sensitive values logged or leaked to unrelated operation | pendiente | pendiente | Not run |

## SE: Settings and configuration

Flutter: settings, agent_profiles. GPUI: settings_*, project_config_*. Fixture: BASE/SETTINGS.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SE-001 | Pane inventory | All eleven sections | Visit every pane using mouse and keyboard | No crash, missing UI or wrong section | en curso | pendiente | Both clients opened all 11 included panes without panic. Control-state/keyboard variants pending; Mobile first Flutter frame still loading. F-003/F-006/F-007/F-008. Evidence SE-001-*. |
| SE-002 | Settings search | Every setting label and group anchor | Search each indexed control and clear | Matching pane/group visible with correct scroll position | pendiente | pendiente | Not run |
| SE-003 | Settings scroll | Long pages and master/detail resize | Scroll and drag at top/middle/end | Correct thumb travel, fixed headers and no overflow | pendiente | pendiente | Not run |
| SE-004 | Persistence | Change/reopen/relaunch/cross-client | Modify controlled preferences and reload both clients | Same saved values without lost unrelated fields | pendiente | pendiente | Not run |
| SE-005 | Validation | Every numeric/path/enum/text control | Apply boundary/invalid/empty inputs | Safe bounds, errors and no corrupt serialized settings | pendiente | pendiente | Not run |
| SE-006 | Reset | Section defaults and cancellation | Reset controlled section; preserve others | Correct scope and freshly synchronized widgets | pendiente | pendiente | Not run |
| SE-007 | Project draft | Save A then edit B or reopen A | Delay/reorder read/save responses | Wrong-generation response cannot change current draft | pendiente | pendiente | Not run |
| SE-008 | Project draft | Edit during refresh/save | Refresh with unsaved text/copy/setup inputs | Live input values survive late responses | pendiente | pendiente | Not run |
| SE-009 | Keyboard settings | Record/conflict/disable/reset | Remap fixtures and restore originals | Registry and terminal-first policy agree | pendiente | pendiente | Not run |
| SE-010 | Controls | Skill runners and host settings | Inspect pending/error/disabled install controls | Correct commands and no unsupported/global mutation | pendiente | pendiente | Not run |

## ST: Status bar quotas and usage

Flutter: agent_quota, agent_usage, keep_alive. GPUI: status_bar.rs, status_quota*, status_usage.rs, keep_alive.rs. Fixture: QUOTAS.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ST-001 | Providers | All provider logos and aliases | Show configured/unconfigured/multiple profiles | No missing Claude/Kimi/MiniMax/Grok icons or labels | pendiente | pendiente | Not run |
| ST-002 | Quota state | Loading/empty/error/stale/exhausted | Drive provider fixtures and safe live reads | Correct bars, percentages, labels, countdowns and errors | pendiente | pendiente | Not run |
| ST-003 | Quota ordering | Pin/unpin/reorder and relaunch | Use fixture configuration | Chips and overview agree with persisted settings | pendiente | pendiente | Not run |
| ST-004 | Quota detail | Per-provider and overview popup | Open cards near both viewport edges | Correct placement, scroll, dimensions and content | en curso | pendiente | F-014 revalidated: Kimi/MiniMax/Z.ai visible and OpenCode Go/Zen prefixed once. Paired regional crops ST-004-gpui-after-crop / ST-004-flutter-recheck-crop. Typography/spacing, per-provider and edge variants pending. No resets used. |
| ST-005 | Popover lifecycle | Hover/delay/pin/same trigger/outside | Framework clock tests plus available native gestures | Hover closes with Flutter delay; click pin persists until dismissal | pendiente | pendiente | Not run |
| ST-006 | Usage | Accounts/range/loading/error/list | Inspect usage views with long fixture data | Correct grouping, time range and totals | pendiente | pendiente | Not run |
| ST-007 | Keep Alive | Toggle and process lifecycle | Use isolated session assertion | Setting and inhibitor ownership correct on quit | pendiente | pendiente | Not run |
| ST-008 | Status layout | Narrow/wide and many providers | Resize while quotas/resources/runtime visible | No downward glitch, clipped controls or overlap | pendiente | pendiente | Not run |

## RT: Runtime and resource manager

Flutter: runtime_host, resource_manager. GPUI: status_runtime.rs, status_resource*. Fixture: RUNTIME.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RT-001 | Resources | Absent/measuring/normal/orphan metrics | Use process fixtures and real owned sessions | Absent is not zero; CPU normalized; no double-count | pendiente | pendiente | Not run |
| RT-002 | Resources | Sort/hierarchy/collapse/scroll | Sort all columns with long nested fixture | Stable hierarchy and missing-values ordering | pendiente | pendiente | Not run |
| RT-003 | Resources | Terminate/restart/cancel | Use only owned disposable processes | Correct confirmation, target cleanup and refresh | pendiente | pendiente | Not run |
| RT-004 | Runtime | Stopped/start/running/reconnect | Control isolated host lifecycle | Start works, status invalidates, terminals recover | pendiente | pendiente | Not run |
| RT-005 | Runtime | Busy stop/force/cancel | Retained sessions on isolated host | No unrelated host termination or stale status | pendiente | pendiente | Not run |
| RT-006 | Runtime | Version mismatch/update/failure | Use controlled older/incompatible host fixtures | Correct distinction, safe replacement and recovery | pendiente | pendiente | Not run |
| RT-007 | Coexistence | Flutter and GPUI same test host | Create/close/rename fixtures in either client | Notifications and layout/state converge without duplication | pendiente | pendiente | Not run |
| RT-008 | Protocol | Requests during disconnect/quit | Interrupt bounded operations | Requests settle; reconnect does not resurrect quit UI | pendiente | pendiente | Not run |

## OM: Orchestration and Agent Canvas

Flutter: orchestration, agent_canvas. GPUI: run_policy*, agent_canvas.rs. Fixture: AGENTS/RUNS.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OM-001 | Run policy | Empty/loading/draft/approved/rejected | Drive deterministic run fixtures | Correct stages, roles, icons, controls and validation | pendiente | pendiente | Not run |
| OM-002 | Run actions | Approve/reject/stop/cancel/interrupt | Use bounded disposable runs | Correct confirmation and no unintended dispatch | pendiente | pendiente | Not run |
| OM-003 | Run lifecycle | Late response after workspace/tab close | Switch/remove fixture while waiting | No resurrected run, stale state or leaked subscription | pendiente | pendiente | Not run |
| OM-004 | Canvas | Empty/content/gate/decision/error | Publish controlled cards and decisions | Rendering and input schema match expected contract | fallo | pendiente | F-011 empty split/detail and filter control differ from Flutter. Published-content and decision variants still pending. |
| OM-005 | Automations | List/create/edit/enable/history/error | Use disabled/non-executing fixture schedules first | Stable IDs, validation, persistence and safe execution boundary | pendiente | pendiente | Not run |

## MB: Mobile and terminal driver

Flutter: mobile_devices. GPUI: mobile_access*, mobile_driver.rs. Fixture: MOBILE.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MB-001 | Gateway | Modes/port/endpoint/validation/error | Configure isolated local gateway | Correct capability state and no accidental public exposure | pendiente | pendiente | Not run |
| MB-002 | Pairing | QR/offer/cancel/expired | Create test offer and cancel | One-time token lifecycle and no reused secret | pendiente | pendiente | Not run |
| MB-003 | Devices | Empty/active/revoked/rename | Use disposable paired device fixture | Correct identity, actions and disabled states | pendiente | pendiente | Not run |
| MB-004 | Revocation | Confirmation/cancel/backend regression | Use disposable pairing under safety gate | No impact on personal paired devices | pendiente | pendiente | Not run |
| MB-005 | Driver | Pause/collapse/reclaim one/all | Attach controlled driver to fixture terminals | Keyboard ownership and recovery correct | pendiente | pendiente | Not run |

## DG: Diagnostics accessibility and performance

Flutter: diagnostics, keyboard, app_window. GPUI: app_log.rs, app_lifecycle.rs, settings_actions. Fixture: BASE/PERF.

| ID | Component | Scenario | Actions | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DG-001 | Diagnostics | Open logs/export/cancel/failure | Export to fixture destination or simulate denied write | Correct ZIP, metadata, error and redaction | pendiente | pendiente | Not run |
| DG-002 | CLI environment | Registration/reload/collision | Use isolated registration target | No overwrite of personal shim; GUI login environment works | pendiente | pendiente | Not run |
| DG-003 | Accessibility | Roles/names/states and keyboard traversal | Inspect each exposed control and operate by keyboard | No missing label, focus trap, duplicate ID or pointer-only action | pendiente | pendiente | Not run |
| DG-004 | Processes | Quit/disconnect/error ownership | Inspect owned UI/host/session processes | No orphan fixture child or killing unrelated runtime | pendiente | pendiente | Not run |
| DG-005 | Cycles | 20 open-close view/tab cycles | Repeat deterministic lifecycle sequence | No state drift, panic or retained entity growth | pendiente | pendiente | Not run |
| DG-006 | Stress | Repeated drag/drop/cancel and races | Run bounded stress suite | No stuck overlay, dropped update or data loss | pendiente | pendiente | Not run |
| DG-007 | Performance | Startup/idle/stream/restore baselines | Same fixture, profile and viewport; separate processes | Comparable measurements and explained regressions | pendiente | pendiente | Not run |
| DG-008 | Release soak | 30 minutes mixed use | Alternate editor/search/splits/agents/reconnect | No panic, loss, leak trend or persistent busy state | pendiente | pendiente | Not run |

## KB: Registered keyboard actions

Source: `keyboard_settings.rs` and the Flutter keyboard action registry. For each action also verify menu/palette parity, disabled state and the terminal-first policy. Fixture: BASE/TABS/GIT.

| ID | Registry action | Expected action | Scenario | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- |
| KB-001 | openSettings / Open Settings | Open the settings dialog. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-002 | openQuickOpen / Quick Open | Search and open a file in the active workspace. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-003 | openCommandPalette / Command Palette | Search and run an Alera command. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-004 | addProject / Add Project | Open the add-project dialog. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-005 | toggleSidebar / Toggle Sidebar | Collapse or expand the project sidebar. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-006 | createWorkspace / New Workspace | Create a linked workspace for the active Git project. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-007 | navigateBack / Go Back | Go to the previously selected workspace. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Legacy goBack overrides migrate without replacing canonical user bindings; unit regression passes. Native pending. |
| KB-008 | navigateForward / Go Forward | Go to the next workspace in navigation history. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Legacy goForward overrides migrate; unit regression passes. Native pending. |
| KB-009 | findInFiles / Find in Files | Open workspace search. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-010 | findInTerminal / Find in Terminal | Search the active terminal scrollback. | Invoke actual binding in Global scope and in terminal focus; restore state | pendiente | pendiente | F-008 corrects the registry group; native pending. |
| KB-011 | toggleTerminalComposer / Toggle Terminal Composer | Show or hide the prompt composer for the active terminal. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-012 | replaceInFiles / Replace in Files | Open workspace search and replace. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-013 | saveFile / Save File | Save the active editor file. | Invoke actual binding in Workspace scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-014 | newTerminalTab / New Terminal Tab | Open a terminal tab in the active workspace. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-015 | closeTab / Close Tab | Close the active terminal tab. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-016 | nextTab / Next Tab | Select the next tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-017 | previousTab / Previous Tab | Select the previous tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-018 | goToTab1 / Go to Tab 1 | Select the first tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-019 | goToTab2 / Go to Tab 2 | Select the second tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-020 | goToTab3 / Go to Tab 3 | Select the third tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-021 | goToTab4 / Go to Tab 4 | Select the fourth tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-022 | goToTab5 / Go to Tab 5 | Select the fifth tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-023 | goToTab6 / Go to Tab 6 | Select the sixth tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-024 | goToTab7 / Go to Tab 7 | Select the seventh tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-025 | goToTab8 / Go to Tab 8 | Select the eighth tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-026 | goToTab9 / Go to Last Tab | Select the last tab in the active pane. | Invoke actual binding in Tabs scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-027 | splitRight / Split Right | Split the active pane to the right with a new terminal. | Invoke actual binding in Panes scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-028 | splitDown / Split Down | Split the active pane downward with a new terminal. | Invoke actual binding in Panes scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-029 | closeSplit / Close Split | Merge the active pane back into its sibling. | Invoke actual binding in Panes scope and in terminal focus; restore state | pendiente | pendiente | Not run |
| KB-030 | openAutomations / Open Automations | Open the automation catalog. | Invoke Mod+Shift+A in Global scope and in terminal focus; close/reopen | en curso | pendiente | Cmd+Shift+A opens from terminal focus in rebuilt debug; repeated shortcut preserves the new editor draft. KB-030-gpui-debug / AU-003-gpui-repeat-shortcut-draft. Flutter native shortcut and reopen variants pending. |

## IN: Individually registered settings inputs

Sources: `app_helpers.rs`, `ai_assist_settings_catalog.rs`, `settings_actions.rs` and the matching Flutter pane. Fixture: SETTINGS. Values and bounds must be read from both controllers before executing the row; no guessed validation rule is accepted.

| ID | Input key | Scenario / action | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- | --- |
| IN-001-edit | host-empty-seconds | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-001-boundary | host-empty-seconds | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-001-persist | host-empty-seconds | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-002-edit | host-detached-seconds | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-002-boundary | host-detached-seconds | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-002-persist | host-detached-seconds | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-003-edit | editor-tab-size | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-003-boundary | editor-tab-size | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-003-persist | editor-tab-size | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-004-edit | editor-autosave-delay | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-004-boundary | editor-autosave-delay | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-004-persist | editor-autosave-delay | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-005-edit | terminal-font-size | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-005-boundary | terminal-font-size | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-005-persist | terminal-font-size | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-006-edit | terminal-font-weight | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-006-boundary | terminal-font-weight | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-006-persist | terminal-font-weight | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-007-edit | terminal-line-height | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-007-boundary | terminal-line-height | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-007-persist | terminal-line-height | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-008-edit | terminal-cursor-opacity | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-008-boundary | terminal-cursor-opacity | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-008-persist | terminal-cursor-opacity | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-009-edit | terminal-background-opacity | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-009-boundary | terminal-background-opacity | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-009-persist | terminal-background-opacity | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-010-edit | terminal-padding-x | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-010-boundary | terminal-padding-x | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-010-persist | terminal-padding-x | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-011-edit | terminal-padding-y | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-011-boundary | terminal-padding-y | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-011-persist | terminal-padding-y | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-012-edit | terminal-tui-scroll | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-012-boundary | terminal-tui-scroll | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-012-persist | terminal-tui-scroll | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-013-edit | terminal-scrollback-lines | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-013-boundary | terminal-scrollback-lines | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-013-persist | terminal-scrollback-lines | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-014-edit | terminal-host-scrollback-mb | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-014-boundary | terminal-host-scrollback-mb | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-014-persist | terminal-host-scrollback-mb | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-015-edit | terminal-buffer-budget-mb | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-015-boundary | terminal-buffer-budget-mb | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-015-persist | terminal-buffer-budget-mb | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-016-edit | terminal-word-separators | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-016-boundary | terminal-word-separators | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-016-persist | terminal-word-separators | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-017-edit | terminal-color-foreground | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-017-boundary | terminal-color-foreground | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-017-persist | terminal-color-foreground | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-018-edit | terminal-color-background | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-018-boundary | terminal-color-background | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-018-persist | terminal-color-background | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-019-edit | terminal-color-cursor | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-019-boundary | terminal-color-cursor | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-019-persist | terminal-color-cursor | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-020-edit | terminal-color-selection | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-020-boundary | terminal-color-selection | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-020-persist | terminal-color-selection | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-021-edit | ai-custom-command | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-021-boundary | ai-custom-command | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-021-persist | ai-custom-command | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-022-edit | quota-env-kimiApiKey | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-022-boundary | quota-env-kimiApiKey | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-022-persist | quota-env-kimiApiKey | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-023-edit | quota-env-zaiApiKey | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-023-boundary | quota-env-zaiApiKey | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-023-persist | quota-env-zaiApiKey | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-024-edit | quota-env-zaiBaseUrl | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-024-boundary | quota-env-zaiBaseUrl | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-024-persist | quota-env-zaiBaseUrl | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-025-edit | quota-env-minimaxApiKey | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-025-boundary | quota-env-minimaxApiKey | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-025-persist | quota-env-minimaxApiKey | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-026-edit | quota-env-minimaxApiHost | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-026-boundary | quota-env-minimaxApiHost | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-026-persist | quota-env-minimaxApiHost | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-027-edit | ai-instructions-commitMessage | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-027-boundary | ai-instructions-commitMessage | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-027-persist | ai-instructions-commitMessage | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-028-edit | ai-instructions-pullRequestDetails | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-028-boundary | ai-instructions-pullRequestDetails | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-028-persist | ai-instructions-pullRequestDetails | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-029-edit | ai-instructions-readingDiff | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-029-boundary | ai-instructions-readingDiff | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-029-persist | ai-instructions-readingDiff | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-030-edit | ai-instructions-workspaceIdentity | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-030-boundary | ai-instructions-workspaceIdentity | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-030-persist | ai-instructions-workspaceIdentity | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |
| IN-031-edit | ai-instructions-speechMessage | Focus, select, replace and undo controlled value | Correct visible value, focus and undo without altering another field | pendiente | pendiente | Not run |
| IN-031-boundary | ai-instructions-speechMessage | Empty, long, Unicode and boundary/invalid values where applicable | Same Flutter validation/sanitization, no panic or invalid persistent state | pendiente | pendiente | Not run |
| IN-031-persist | ai-instructions-speechMessage | Save, leave pane, reopen and relaunch both clients | Exact scoped value restored; unrelated settings unchanged | pendiente | pendiente | Not run |

## AU: Automation actions

Sources: `automations.rs` and Flutter `automations` feature. Fixture: disabled/non-executing definitions in isolated runtime; external or process-spawning actions require their safety checks.

| ID | Action / scenario | Expected | D | R | Observed / evidence |
| --- | --- | --- | --- | --- | --- |
| AU-001 | Catalog filters and empty/error/loading | Correct selection and list state | fallo | pendiente | F-013: empty catalog/layout/action placement differs; both opened from native menu. Populated/filter/error variants pending. Evidence AU-001-*-empty. |
| AU-002 | Create disabled automation and validate schedule | No accidental autostart or execution | pendiente | pendiente | Not run |
| AU-003 | Edit definition with late read/save response | Draft and identity preserved | en curso | pendiente | New editor opens, Name edit survives repeated shortcut, Cancel returns to empty catalog without saving. Epoch/snapshot tests pass; delayed read/save integration and populated selection remain pending. AU-003-gpui-*. |
| AU-004 | Clone and reorder/select records | New identity, stable row actions | pendiente | pendiente | Not run |
| AU-005 | Enable/disable safe fixture | Runtime and UI agree without duplicate jobs | pendiente | pendiente | Not run |
| AU-006 | Manual run/cancel bounded fixture | Correct run state and owned-process cleanup | pendiente | pendiente | Not run |
| AU-007 | Run history and audit details | Correct detail identity, pagination and errors | pendiente | pendiente | Not run |
| AU-008 | Import/export valid and malformed fixture JSON | Clear validation; no unrelated definition overwritten | pendiente | pendiente | Not run |
| AU-009 | Project policy and retention settings | Correct scope, defaults and persistence | pendiente | pendiente | Not run |

## Scope and crosswalk

- Coverage: 302 executable scenario rows, including 30 shortcuts, 31 individual input keys across three scenarios each, and nine explicit Automation actions. Open Automations and cross-workspace editor ownership were added during reconciliation. This is a starting catalog, not a ceiling; new controls, actions and state transitions found in code are added before their domain is closed. Split domain detail into linked files if this index approaches 500 lines.
- Excluded: AI Dictation; Codex Chat; tray/Dock/badges/hide-on-close; Browser; PDF; Account/OAuth; SSH/LSP; emulator embedding; full updater. Runtime update remains included. Existing adjacent controls are audited for stability without expanding these features.
- AI Dictation: excluido by explicit user direction during this audit. SCOPE-001 is resolved; no microphone, transcription or dictation provider UI is to be added to GPUI. AI Assist/Reading Diff/Text Actions/Speech Messages remain included.
- Additional current features explicitly mapped: agent_usage -> ST; automations -> OM and SE; command_terminal -> TE; keep_alive -> ST; reading_diff -> AI/PV; agent_canvas -> OM. All 32 Flutter feature directories therefore have an included, excluded or scope-review mapping.
- Native hover and actual IME composition are separate from framework event tests. Sky currently lacks pure pointer movement. Unsupported gestures are not inferred from a click.

## Execution ledger

- 2026-08-30T04:04Z: baseline recorded and goal active; all scenario gates pending. Preparing isolated profile before UI mutation. No current result imported from earlier reports.
- 2026-08-30: ENV-001 verified using bundle identities plus actual open database paths. Unique staged Flutter/GPUI bundle paths are required to avoid stale Sky resolver identities. SH-001 debug captured; F-003 recorded. AI Dictation explicitly excluded by the user.
- 2026-08-30: WS-001 registration subcase passed through both native UIs; duplicate handling remains pending, so the scenario is not yet validated. F-005 isolates dialog parity gaps. TREE fixture seeded through `alera-cli`: Alpha root -> Child -> Grandchild plus sibling Readme report; Beta root remains independent.
- 2026-08-30: three fixture projects/six workspaces and a shared Alpha terminal now exist. Both clients completed the eleven-pane Settings opening sweep. Settings root was changed through GPUI UI and verified in the isolated runtime, not the personal profile. F-006/F-007/F-008 recorded; no fixes applied before the broad pass.
- 2026-08-30: same rich Markdown opened via both Explorers. F-009 table contrast/layout confirmed; REF-001 separates a Flutter inline-SVG failure from GPUI behavior. Remaining preview and editor cases are pending.
