/**
 * Every string the demo quotes from the app, with the file that says it.
 * `literal` is the exact text to find in that file when the demo fills in a
 * template (`{agent} needs attention` becomes "Claude needs attention"); the
 * fidelity tests fail when a source file stops containing it, so the demo
 * cannot keep showing copy the app no longer uses.
 */
export interface AppCopy {
  text: string;
  source: string;
  literal?: string;
}

const WORKBENCH = 'lib/src/features/workbench';
const PULL_REQUESTS = 'lib/src/features/pull_requests';

const AGENT_STATUS_BADGE = `${WORKBENCH}/presentation/widgets/agent_run_status_badge.dart`;

export const APP_COPY = {
  needsInput: { text: 'Needs Input', source: AGENT_STATUS_BADGE },
  blockedBadge: { text: 'Blocked', source: AGENT_STATUS_BADGE },
  doneBadge: { text: 'Done', source: AGENT_STATUS_BADGE },
  newWorkspace: { text: 'New Workspace', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  fromPrompt: { text: 'From Prompt', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  manual: { text: 'Manual', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  projectFolder: { text: 'Project Folder', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  newWorktree: { text: 'New Worktree', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  sourceBranch: { text: 'Source Branch', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  projectField: { text: 'Project', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  parentWorkspace: { text: 'Parent Workspace', source: `${WORKBENCH}/presentation/workspace_graph_dialogs.dart` },
  noParent: { text: 'No Parent', source: `${WORKBENCH}/presentation/workspace_graph_dialogs.dart` },
  hostField: { text: 'Host', source: `${WORKBENCH}/presentation/workspace_host_picker.dart` },
  thisDevice: { text: 'This Device', source: `${WORKBENCH}/presentation/workspace_host_picker.dart` },
  hostHelper: {
    text: 'Add SSH hosts in Settings → Remote Hosts to create workspaces on another machine.',
    source: `${WORKBENCH}/presentation/workspace_host_picker.dart`,
  },
  issueUrl: { text: 'Issue URL', source: 'lib/src/features/linked_issues/presentation/issue_url_field.dart' },
  createAnother: { text: 'Create Another', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  agentProfile: { text: 'Agent Profile', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  initialPrompt: { text: 'Initial Prompt', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  initialPromptHint: {
    text: 'Describe what the agent should build or paste an image',
    source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart`,
  },
  createAndStartAgent: { text: 'Create And Start Agent', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  jobCreatingFromPrompt: { text: 'Creating workspace from prompt', source: `${WORKBENCH}/application/background_setup_jobs.dart` },
  phaseIdentity: { text: 'Generating workspace identity', source: `${WORKBENCH}/application/prompt_workspace_pipeline.dart` },
  phaseBranch: { text: 'Checking generated branch', source: `${WORKBENCH}/application/prompt_workspace_pipeline.dart` },
  phaseCreating: { text: 'Creating workspace', source: `${WORKBENCH}/application/prompt_workspace_pipeline.dart` },
  phaseStartingAgent: { text: 'Starting agent', source: `${WORKBENCH}/application/prompt_workspace_pipeline.dart` },
  workspaceCreated: { text: 'Workspace created', source: `${WORKBENCH}/presentation/workbench_dialog_launchers_create_workspace.dart` },
  searchWorkspaces: { text: 'Search workspaces', source: `${WORKBENCH}/presentation/project_workbench_sidebar_shell.dart` },
  splitRight: { text: 'Split Right', source: `${WORKBENCH}/presentation/workspace_panel_menus.dart` },
  driverTitle: {
    text: 'Pixel 7a is driving this terminal',
    source: `${WORKBENCH}/presentation/mobile_driver_overlay.dart`,
    literal: 'is driving this terminal',
  },
  driverPaused: { text: 'Desktop keyboard is paused', source: `${WORKBENCH}/presentation/mobile_driver_overlay.dart` },
  takeBackTerminal: { text: 'Take Back This Terminal', source: `${WORKBENCH}/presentation/mobile_driver_overlay.dart` },
  generateCommitMessage: {
    text: 'Generate commit message with AI',
    source: `${WORKBENCH}/presentation/workspace_git_diff_panel_toolbar.dart`,
  },
  stageAll: { text: 'Stage All', source: `${WORKBENCH}/presentation/workspace_git_diff_panel_toolbar.dart` },
  publishBranch: { text: 'Publish Branch', source: `${WORKBENCH}/presentation/workspace_git_diff_panel_toolbar.dart` },
  branchPublished: { text: 'Branch published', source: `${WORKBENCH}/presentation/workspace_git_diff_panel.dart` },
  createPullRequest: { text: 'Create Pull Request', source: `${PULL_REQUESTS}/presentation/pull_request_composer_actions.dart` },
  generatePullRequestDetails: {
    text: 'Generate Title And Description With AI',
    source: `${PULL_REQUESTS}/presentation/pull_request_composer_actions.dart`,
  },
  askAgent: { text: 'Ask Agent', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  watchAndFix: { text: 'Watch and Fix', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  watchingFix: { text: 'Watching: Fix', source: `${PULL_REQUESTS}/domain/pull_request_agent_watch.dart` },
  resourceManager: { text: 'Resource Manager', source: 'lib/src/features/resource_manager/presentation/resource_status_panel_chrome.dart' },
  keepAlive: { text: 'Keep Alive', source: 'lib/src/features/keep_alive/presentation/keep_alive_status_chip.dart' },
  pushTitle: {
    text: 'Claude needs attention',
    source: 'rust/alera-cli/src/push_notifications/event.rs',
    literal: '{agent} needs attention',
  },
  pushBody: {
    text: 'Workspace Webhook Retry Backoff in storefront',
    source: 'rust/alera-cli/src/push_notifications/event.rs',
    literal: 'Workspace {workspace} in {project}',
  },
  typeCommand: { text: 'Type a command', source: 'mobile/lib/src/features/terminal/presentation/terminal_compose_bar.dart' },
  projects: { text: 'Projects', source: `${WORKBENCH}/presentation/widgets/workbench_sidebar_toolbar.dart` },
  addProject: { text: 'Add Project', source: `${WORKBENCH}/presentation/project_workbench_sidebar_footer.dart` },
  showAgentRuns: { text: 'Show Agent Runs', source: `${WORKBENCH}/presentation/project_workbench_workspace_rows.dart` },
  expandPanel: { text: 'Expand Panel', source: `${WORKBENCH}/presentation/workspace_context_sidebar.dart` },
  sourceControl: { text: 'Source Control', source: `${WORKBENCH}/domain/workspace_panel.dart` },
  pullRequest: { text: 'Pull Request', source: `${WORKBENCH}/domain/workspace_panel.dart` },
  explorer: { text: 'Explorer', source: `${WORKBENCH}/domain/workspace_panel.dart` },
  search: { text: 'Search', source: `${WORKBENCH}/domain/workspace_panel.dart` },
  terminal: { text: 'Terminal', source: `${WORKBENCH}/presentation/workspace_panel_menus.dart` },
  staged: { text: 'Staged', source: 'lib/src/shared/infra/git/git_diff_models.dart' },
  unstaged: { text: 'Unstaged', source: 'lib/src/shared/infra/git/git_diff_models.dart' },
  noChanges: { text: 'No changes', source: `${WORKBENCH}/presentation/workspace_git_diff_panel_layout.dart` },
  commits: { text: 'COMMITS', source: `${WORKBENCH}/presentation/workspace_git_history_panel.dart`, literal: "'Commits'.toUpperCase()" },
  committed: { text: 'Committed', source: `${WORKBENCH}/presentation/workspace_git_diff_panel.dart` },
  generatingWithAi: { text: 'Generating with AI', source: `${WORKBENCH}/presentation/workspace_git_diff_panel_commit_message_field.dart` },
  commitMessageGenerated: {
    text: 'Commit message generated with Codex',
    source: `${WORKBENCH}/presentation/workspace_git_diff_panel.dart`,
    literal: 'Commit message generated with ${',
  },
  baseBranch: { text: 'Base Branch', source: `${PULL_REQUESTS}/presentation/pull_request_composer_form.dart` },
  description: { text: 'Description', source: `${PULL_REQUESTS}/presentation/pull_request_composer_form.dart` },
  restackChanges: { text: 'Restack Changes', source: `${PULL_REQUESTS}/presentation/pull_request_restack_button.dart` },
  shipChanges: { text: 'Ship Changes', source: `${PULL_REQUESTS}/presentation/pull_request_composer_actions.dart` },
  linkExistingPullRequest: { text: 'Link Existing Pull Request', source: `${PULL_REQUESTS}/presentation/pull_request_composer.dart` },
  pullRequestDetailsGenerated: {
    text: 'Pull request details generated with Codex',
    source: `${PULL_REQUESTS}/presentation/pull_request_composer.dart`,
    literal: 'Pull request details generated with ${',
  },
  stackedPullRequests: { text: 'Stacked Pull Requests', source: `${PULL_REQUESTS}/presentation/pull_request_stack_section.dart` },
  notNativeStack: {
    text: 'This pull request is not part of a native GitHub stack.',
    source: `${PULL_REQUESTS}/presentation/pull_request_stack_section.dart`,
  },
  linkExistingPullRequests: { text: 'Link Existing Pull Requests', source: `${PULL_REQUESTS}/presentation/pull_request_stack_section.dart` },
  noCommentsYet: { text: 'No comments yet', source: `${PULL_REQUESTS}/presentation/pull_request_conversation.dart` },
  startConversation: { text: 'Start the conversation', source: `${PULL_REQUESTS}/presentation/pull_request_conversation.dart` },
  createMergeCommit: { text: 'Create Merge Commit', source: `${PULL_REQUESTS}/domain/review_merge_method.dart` },
  failedChecks: { text: 'Failed Checks', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  reviewComments: { text: 'Review Comments', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  mergeConflicts: { text: 'Merge Conflicts', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  watchFixAndMerge: { text: 'Watch, Fix and Merge', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  checksFailing: {
    text: '1 failing Check',
    source: `${PULL_REQUESTS}/presentation/pull_request_check_list.dart`,
    literal: "'$count failing $noun'",
  },
  checksInProgress: {
    text: '4 in progress Checks',
    source: `${PULL_REQUESTS}/presentation/pull_request_check_list.dart`,
    literal: "'$count in progress $noun'",
  },
  checksSuccessful: {
    text: '4 successful Checks',
    source: `${PULL_REQUESTS}/presentation/pull_request_check_list.dart`,
    literal: "'$count successful $noun'",
  },
  fixFailedChecks: { text: 'Fix Failed Checks', source: `${PULL_REQUESTS}/presentation/pull_request_review_agent_actions.dart` },
  fixPrompt: {
    text: 'Pull request #128 checks failed. Please fix them.',
    source: `${PULL_REQUESTS}/domain/pull_request_agent_prompts.dart`,
    literal: 'checks failed. Please fix them.',
  },
  localHost: { text: 'Local', source: 'lib/src/features/agent_quota/presentation/agent_quota_status_bar_content.dart' },
  voice: { text: 'Voice', source: 'lib/src/features/voice/presentation/voice_status_bar_control.dart' },
  desktopTookBack: {
    text: 'Desktop took back the terminal',
    source: 'mobile/lib/src/features/terminal/presentation/workspace_tabs_screen.dart',
  },
  pushChannel: { text: 'Agent attention', source: 'mobile/lib/src/features/push_notifications/infra/mobile_local_notification_service.dart' },
} as const satisfies Record<string, AppCopy>;

export type AppCopyKey = keyof typeof APP_COPY;

export function copy(key: AppCopyKey): string {
  return APP_COPY[key].text;
}
