# GPUI Exact UI Parity Matrix

This matrix is the completion contract for the GPUI implementation scope agreed in `context.md`. `Done` means the GPUI surface matches the Flutter structure, visual hierarchy, interactive controls, live data and relevant loading, empty, error and confirmation states. A live runtime call without the corresponding product UI is not parity.

Audit note (2026-08-24): the `Done` labels below are historical implementation claims and are not a substitute for live evidence. The current authoritative status is the complete domain inventory in `/Volumes/ExternalStorage/Projects/alera/todo.md`, which downgrades rows to `parcial` or `sin validar` until the corresponding Computer Use scenario is demonstrated.

Explicit POC exclusions remain out of scope: Browser, Updater, PDF preview, Account and OAuth, SSH, LSP, emulator embedding and the final license audit.

## Design System And Interaction Contract

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Exact Lucide icon glyphs and sizing | `alera_icons.dart`; pinned `lucide_icons_flutter` assets | Done |
| Exact VS Code Codicons for source control | `alera_icons.dart`, `alera_codicons.dart` | Done |
| Exact VS Code Material file and folder icons | `alera_file_icon.dart`; `vscode_material_icon_theme` assets | Done |
| Exact agent and provider logo assets | Flutter agent/provider widgets and bundled SVG assets | Done |
| Text inputs: label, placeholder, focus, validation and disabled state | `AleraTextField` and all feature call sites | Done |
| Search fields and option toggles | `AleraSearchField` and all search call sites | Done |
| Dropdowns: trigger, filtering, keyboard selection and disabled entries | `AleraDropdownField` and all feature call sites | Done |
| Dropdown and menu pointer cursor, same-trigger toggle and outside-click dismissal | Shared dropdown and overlay components | Done |
| Checkboxes, radios, switches and segmented controls | Shared design-system controls and all feature call sites | Done |
| Buttons and icon buttons: variants, hover, focus, pressed and busy states | Shared design-system buttons and all feature call sites | Done |
| Menus, tooltips, toasts, dialogs and confirmations | Shared overlay components and all feature call sites | Done |
| Keyboard and pointer semantics for every included action | Action registries, controllers and presentation callbacks | Done |

## Shell And Project Navigation

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Window geometry and zoom | Live `Alera Dev`; `alera_shell_page.dart` | Done |
| Dark tokens and typography | `AleraTokens`, Inter, JetBrains Mono | Done |
| Welcome dashboard | `welcome_dashboard*.dart` | Done |
| Expanded project sidebar | `project_workbench_sidebar*.dart` | Done |
| Collapsed project rail | `project_workbench_collapsed_sidebar.dart` | Done |
| Sidebar resize and persisted width | `sidebar_resize_handle.dart` | Done |
| Workspace filtering and clear | `sidebar_search_bar.dart` | Done |
| Project row actions and menus | `project_workbench_sidebar_actions.dart` | Done |
| Workspace row states, agents, tags and relations | `project_workbench_workspace_rows.dart`, `project_workbench_agent_rows.dart` | Done |
| Workspace actions and confirmation dialogs | `project_workbench_workspace_actions.dart` | Done |
| Add Project local folder | `add_project_dialog.dart` | Done |
| Add Project clone repository | `add_project_dialog.dart` | Done |
| Create Workspace full form and pickers | `create_workspace_dialog*.dart` | Done |
| Prompt Workspace AI flow | `prompt_workspace_dialog*.dart` | Done |

## Workbench And Tabs

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Tab strip geometry and active state | `workspace_workbench_tab_strip*.dart` | Done |
| Create terminal tab | `workspace_workbench_view.dart` | Done |
| Rename and close tab | `workspace_workbench_tab_chips.dart` | Done |
| Tab overflow and action menus | `workspace_workbench_tab_strip.dart` | Done |
| Horizontal and vertical split layout | `workspace_workbench_layout_view.dart` | Done |
| Split resize and persisted ratios | `workspace_workbench_resize_handle.dart` | Done |
| Reorder tabs, move them between groups, and create directional splits by drag | `workspace_workbench_tab_strip_drop.dart`, `workspace_workbench_pane.dart`, `workbench_layout.dart` | Done |
| Active group and tab restoration | `workbench_layout.dart` | Done |
| Dirty-tab close confirmation | `alera_shell_page_body.dart` | Done |
| Mobile driver overlay, paused keyboard, collapse, reclaim one and reclaim all | `mobile_driver_overlay.dart`, `terminal_driver_presence_controller.dart` | Done |

## Context Sidebar

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Header tabs: Explorer, Search, Source Control, Pull Request | `workspace_context_sidebar.dart` | Done |
| Collapse and expand rail | `workspace_context_sidebar.dart` | Done |
| Sidebar resize and persisted width | `workspace_context_sidebar.dart` | Done |
| Explorer panel placement | `workspace_explorer*.dart` | Done |
| Search panel placement | `workspace_search_panel*.dart` | Done |
| Source Control panel placement | `workspace_git_diff_panel*.dart` | Done |
| Pull Request panel placement | `workspace_pull_requests_panel.dart` | Done |

## Terminal

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| PTY attach, snapshot and binary output | `terminal_runtime*.dart` | Done |
| Ordered keyboard input and space handling | `terminal_runtime_interactive_view.dart` | Done |
| Resize and output resync | `terminal_runtime*.dart` | Done |
| Bracketed paste | `terminal_runtime_clipboard.dart` | Done |
| Terminal title in tab | `terminal_surface.dart` | Done |
| Selection and copy | `terminal_runtime_interactive_view.dart` | Done |
| Scroll interaction and scrollbar | `terminal_runtime_rendering.dart` | Done |
| Link hover and open policy | `terminal_link_resolver.dart` | Done |
| Path drop | `terminal_path_drop.dart` | Done |
| Focus, exit and recovery states | `terminal_runtime_session_recovery.dart` | Done |
| Terminal theme from settings | `terminal_theme_controls.dart` | Done |
| Cursor shape, color, opacity and blinking | `terminal_pane.dart`, `terminal_runtime_rendering.dart` | Done |

## Explorer, Search, Editor And Preview

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Explorer tree, icons and lazy expansion | `workspace_explorer*.dart` | Done |
| Explorer toolbar and modes | `workspace_explorer_widgets.dart` | Done |
| New, rename, delete and move actions | `workspace_explorer_actions.dart` | Done |
| Source Control root actions | `workspace_explorer_widgets.dart` | Done |
| Search input and replace disclosure | `workspace_search_panel_inputs.dart` | Done |
| Case, whole word and regex toggles | `workspace_search_panel_toolbar.dart` | Done |
| Include, exclude and ignored-file controls | `workspace_search_panel_toolbar.dart` | Done |
| Search result grouping and match navigation | `workspace_search_panel_results.dart` | Done |
| Replace-one and confirmed replace-all | `workspace_search_panel*.dart` | Done |
| Editor loading, language and dirty indicators | `workspace_editor*.dart` | Done |
| Save and external-conflict confirmation | `workspace_editor_surface.dart` | Done |
| Markdown source and preview modes | `workspace_markdown_viewer_surface.dart` | Done |
| Mermaid preview | `workspace_merman_viewer_surface.dart` | Done |
| Image preview | `workspace_image_preview_surface.dart` | Done |
| Git working-tree and commit diff tabs | `workspace_git_diff_surface*.dart` | Done |

## Source Control

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Toolbar, root scope and refresh controls | `workspace_git_diff_panel_toolbar.dart` | Done |
| Commit message, AI generation and primary split action | `workspace_git_diff_panel.dart` | Done |
| Staged, changes and untracked groups | `workspace_git_diff_panel_groups.dart` | Done |
| Tree and list view modes | `workspace_git_diff_panel_tree.dart` | Done |
| Stage, unstage and discard per path | `workspace_git_diff_panel_rows.dart` | Done |
| Fetch, pull, push, commit and amend | `workspace_git_diff_panel*.dart` | Done |
| Stash and pop dialogs | `workspace_git_diff_panel_stash_dialog.dart` | Done |
| Commit history graph and files | `workspace_git_history_panel*.dart` | Done |
| Destructive confirmations | Git panel dialogs | Done |

## Pull Requests, Checks And AI Text

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| No-PR composer | `pull_request_composer.dart` | Done |
| Base branch, title and description fields | `pull_request_composer.dart` | Done |
| AI generation actions and progress | `pull_request_composer_actions.dart` | Done |
| Link existing pull request | `pull_request_link_form.dart` | Done |
| Existing PR review header and metadata | `pull_request_review_view.dart` | Done |
| Checks list and details | `pull_request_check_list.dart` | Done |
| Comments and reviews | `pull_request_review_comments.dart` | Done |
| Ready, draft, update and close actions | `pull_request_review_actions.dart` | Done |
| Merge, squash and rebase actions | `pull_request_review_actions.dart` | Done |
| AI Text workspace identity generation and cancellation | `prompt_workspace_dialog*.dart` | Done |

## Status Bar And Operational UI

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Quotas, Resource and Runtime hover-open, delayed hover-close, click pin, toggle and outside dismissal | Shared status popover controller | Done |
| Local host indicator | `agent_quota_status_bar.dart` | Done |
| Provider quota chips | `agent_quota_status_bar.dart` | Done |
| Quota loading, error and unpinned states | `agent_quota_status_bar*.dart` | Done |
| Provider quota hover cards | `agent_quota_hover_card.dart` | Done |
| All quotas overview | `agent_quota_overview_panel.dart` | Done |
| Resource summary chip | `resource_status_chip.dart` | Done |
| Resource Manager table, sort and hierarchy | `resource_status_panel*.dart` | Done |
| Resource terminate and restart confirmations | `resource_status_panel_rows.dart` | Done |
| Runtime summary chip | `runtime_host_status_bar.dart` | Done |
| Runtime status popover and actions | `runtime_host_status_panel.dart` | Done |
| Runtime isolated Start and Stop lifecycle | `runtime_host_lifecycle_service.dart` | Done |
| Runtime build mismatch, Update and force confirmation | `runtime_host_lifecycle_service.dart` | Partial |

## Settings And Included Administrative Areas

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Full-width settings dialog and search | `settings_dialog*.dart` | Done |
| Application, runtime and diagnostics pane | `application_pane.dart` | Done |
| Agents and skill controls | `agents_pane.dart` | Done |
| Provider quota settings | `agent_quota_settings_group.dart` | Done |
| AI Text settings | `ai_text_pane.dart` | Done |
| Editor settings | `editor_pane.dart` | Done |
| Terminal settings and theme picker | `terminal_pane.dart`, `terminal_theme_picker.dart` | Done |
| Keyboard shortcuts | `keyboard_settings_pane.dart` | Done |
| Project configuration | `projects_pane.dart`, `project_config_editor*.dart` | Done |
| Mobile status, gateway modes, one-time QR, pairing cancellation, rename, revoke and delete | `mobile_devices_pane.dart`, `mobile_pairing*.dart` | Done |
| Agent profile list and editor | `agent_profiles_pane*.dart` | Done |
| Diagnostics export and log controls | `application_diagnostics_section.dart` | Done |

## Orchestration And Confirmations

| Surface | Flutter Reference | GPUI Gate |
| --- | --- | --- |
| Run policy review dialog | `run_policy_review_dialog.dart` | Done |
| Run policy stages | `run_policy_stage_list.dart` | Done |
| Live run, task, gate and terminal state | Runtime protocol v2 | Done |
| Typed mutation controls | Runtime protocol v2 | Done |
| Confirmations for stop, cancel, interrupt and reset | Runtime protocol v2 | Done |

## Validation Gates

| Gate | Requirement | Status |
| --- | --- | --- |
| Visual comparison | Flutter and GPUI at the same macOS zoomed window size | Done |
| Interactive comparison | Every row above exercised in both clients when data permits | Done |
| Loading and empty states | Captured and compared for every asynchronous surface | Done |
| Error and confirmation states | Captured and compared without destructive completion | Done |
| Runtime smoke | All included verbs remain operational | Done |
| Rust quality | Format, Clippy with warnings denied and all GPUI tests | Done |
| Flutter regression | Focused shared-helper tests and app startup | Done |
| Single GPUI instance | `make gpui-debug` leaves exactly one process | Done |
| File size and repository style | No file over 500 lines, no em dash, clean diff check | In Progress |
