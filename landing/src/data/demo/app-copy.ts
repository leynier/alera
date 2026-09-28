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

export const APP_COPY = {
  newWorkspace: { text: 'New Workspace', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  fromPrompt: { text: 'From Prompt', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  manual: { text: 'Manual', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_shell.dart` },
  projectFolder: { text: 'Project Folder', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  newWorktree: { text: 'New Worktree', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  sourceBranch: { text: 'Source Branch', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  agentProfile: { text: 'Agent Profile', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  initialPrompt: { text: 'Initial Prompt', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
  initialPromptHint: {
    text: 'Describe what the agent should build or paste an image',
    source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart`,
  },
  cancel: { text: 'Cancel', source: `${WORKBENCH}/presentation/prompt_workspace_dialog_form.dart` },
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
} as const satisfies Record<string, AppCopy>;

export type AppCopyKey = keyof typeof APP_COPY;

export function copy(key: AppCopyKey): string {
  return APP_COPY[key].text;
}
