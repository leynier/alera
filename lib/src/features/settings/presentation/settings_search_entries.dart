import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_reading_diff.dart';

const List<SettingsSearchEntry>
applicationSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Workspace Directory',
    description: 'Where new linked workspaces are created on disk.',
    keywords: <String>['worktree', 'folder', 'location', 'path'],
    groupId: 'storage',
  ),
  SettingsSearchEntry(
    title: 'Confirm Project Removal',
    description: 'Ask before unregistering a project.',
    keywords: <String>['safety', 'destructive', 'remove', 'delete'],
    groupId: 'safety',
  ),
  SettingsSearchEntry(
    title: 'Confirm Workspace Removal',
    description: 'Ask before removing a workspace worktree.',
    keywords: <String>['safety', 'destructive', 'remove', 'delete'],
    groupId: 'safety',
  ),
  SettingsSearchEntry(
    title: 'Keep Runtime Open When App Quits',
    description: 'Leave the app-launched sidecar running after a clean quit.',
    keywords: <String>[
      'host',
      'sidecar',
      'lifecycle',
      'quit',
      'shutdown',
      'leave',
    ],
    groupId: 'runtime',
  ),
  SettingsSearchEntry(
    title: 'Empty Host Shutdown',
    description:
        'Stop the terminal host after the app closes with no sessions.',
    keywords: <String>['host', 'sidecar', 'lifetime', 'timeout'],
    groupId: 'runtime',
  ),
  SettingsSearchEntry(
    title: 'Detached Session Shutdown',
    description:
        'Stop detached running terminal sessions after the app stays closed.',
    keywords: <String>['host', 'sidecar', 'session', 'timeout'],
    groupId: 'runtime',
  ),
  SettingsSearchEntry(
    title: 'Open Logs Folder',
    description: 'Show the folder holding the app log files.',
    keywords: <String>['log', 'logs', 'diagnostics', 'debug', 'folder'],
    groupId: 'diagnostics',
  ),
  SettingsSearchEntry(
    title: 'Export Diagnostics',
    description: 'Save app and runtime logs with version details as a zip.',
    keywords: <String>[
      'log',
      'logs',
      'diagnostics',
      'export',
      'bundle',
      'report',
      'zip',
    ],
    groupId: 'diagnostics',
  ),
  SettingsSearchEntry(
    title: 'Log Level',
    description: 'How much detail is written to the log files.',
    keywords: <String>['log', 'verbose', 'debug', 'diagnostics'],
    groupId: 'diagnostics',
  ),
  SettingsSearchEntry(
    title: 'Send Crash Reports',
    description: 'Send crashes to Sentry, an external service.',
    keywords: <String>['crash', 'sentry', 'telemetry', 'report', 'error'],
    groupId: 'diagnostics',
  ),
  SettingsSearchEntry(
    title: 'Updates',
    description: 'Check desktop releases for this platform.',
    keywords: <String>['release', 'download', 'version'],
    groupId: 'updates',
  ),
  SettingsSearchEntry(
    title: 'Star Alera on GitHub',
    description: 'Show your support for the project.',
    keywords: <String>['support', 'github', 'star'],
    groupId: 'support',
  ),
];

const List<SettingsSearchEntry> agentsSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'All Alera Skills',
    description: 'Install or update every Alera agent skill.',
    keywords: <String>[
      'all',
      'install',
      'update',
      'skills',
      'computer use',
      'emulator',
      'orchestration',
    ],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Alera CLI Skill',
    description: 'Install agent instructions for the Alera CLI.',
    keywords: <String>['codex', 'skill', 'cli', 'agent', 'workspace'],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Agent Canvas Skill',
    description:
        'Install agent instructions for publishing structured updates in Agent Canvas.',
    keywords: <String>[
      'agent canvas',
      'canvas',
      'skill',
      'agent',
      'publish',
      'decision',
    ],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Alera Orchestration Skill',
    description: 'Install agent instructions for Alera orchestration.',
    keywords: <String>[
      'orchestration',
      'skill',
      'agent',
      'handoff',
      'task',
      'dispatch',
    ],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Alera Computer Use Skill',
    description: 'Install agent instructions for desktop computer use.',
    keywords: <String>[
      'computer use',
      'desktop',
      'accessibility',
      'skill',
      'agent',
      'click',
      'window',
    ],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Codex Hooks',
    description: 'Use Alera-managed Codex runtime hooks.',
    keywords: <String>['codex', 'agent', 'status', 'hooks'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Claude Code Hooks',
    description: 'Use an Alera-managed Claude Code config with status hooks.',
    keywords: <String>['claude', 'agent', 'status', 'hooks'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'GitHub Copilot Hooks',
    description: 'Use an Alera-managed GitHub Copilot home overlay.',
    keywords: <String>['copilot', 'github', 'agent', 'status', 'hooks'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Cursor Hooks',
    description: 'Use an Alera-managed Cursor agent plugin wrapper.',
    keywords: <String>['cursor', 'agent', 'status', 'hooks', 'cli'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Antigravity Hooks',
    description: 'Install managed Antigravity hooks for the agy CLI.',
    keywords: <String>['antigravity', 'agy', 'agent', 'status', 'hooks'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'OpenCode Hooks',
    description: 'Install managed OpenCode status plugin.',
    keywords: <String>['opencode', 'agent', 'status', 'hooks', 'plugin'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'OpenCode 2 Hooks',
    description: 'Install managed OpenCode 2 status plugin.',
    keywords: <String>[
      'opencode',
      'opencode2',
      'agent',
      'status',
      'hooks',
      'plugin',
      'v2',
    ],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Pi Hooks',
    description: 'Install managed Pi status extension.',
    keywords: <String>['pi', 'agent', 'status', 'hooks', 'extension'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Amp Hooks',
    description: 'Use an Alera-managed Amp config overlay.',
    keywords: <String>['amp', 'agent', 'status', 'hooks', 'plugin'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Grok Build Hooks',
    description: 'Install managed Grok Build status hooks.',
    keywords: <String>['grok', 'xai', 'agent', 'status', 'hooks'],
    groupId: 'hooks',
  ),
  SettingsSearchEntry(
    title: 'Agent Status Notifications',
    description: 'Show native notifications when agents need attention.',
    keywords: <String>[
      'codex',
      'claude',
      'copilot',
      'cursor',
      'antigravity',
      'agy',
      'opencode',
      'opencode2',
      'pi',
      'amp',
      'grok',
      'agent',
      'status',
      'notification',
    ],
    groupId: 'behavior',
  ),
  SettingsSearchEntry(
    title: 'Agent Finished Notifications',
    description: 'Also notify when an agent finishes a turn.',
    keywords: <String>[
      'agent',
      'status',
      'notification',
      'finished',
      'done',
      'turn',
    ],
    groupId: 'behavior',
  ),
  SettingsSearchEntry(
    title: 'Keep Computer Awake While Agents Are Working',
    description: 'Keep this computer and display awake during agent work.',
    keywords: <String>[
      'awake',
      'sleep',
      'power',
      'agent',
      'working',
      'lid',
      'display',
    ],
    groupId: 'behavior',
  ),
];

const List<SettingsSearchEntry> quotaSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Provider Quotas',
    description: 'Choose quota providers and their display order.',
    keywords: <String>[
      'quota',
      'usage',
      'codex',
      'kimi',
      'grok',
      'antigravity',
      'minimax',
      'z.ai',
      'order',
      'pin',
      'pinned',
      'status bar',
    ],
    groupId: 'providers',
  ),
  SettingsSearchEntry(
    title: 'Claude Code Quotas',
    description: 'Enable Claude quotas for default and CCS accounts.',
    keywords: <String>['claude', 'quota', 'usage'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude Default Quotas',
    description: 'Configure the default Claude account independently.',
    keywords: <String>['claude', 'default', 'account', 'quota'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude CCS Profiles',
    description: 'Configure CCS alias and profile pairs for Claude quotas.',
    keywords: <String>[
      'claude',
      'ccs',
      'profile',
      'alias',
      'quota',
      'pin',
      'pinned',
      'status bar',
    ],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Kimi API Key Variable',
    description: 'Configure the Kimi API key environment variable name.',
    keywords: <String>['kimi', 'environment', 'api key', 'KIMI_API_KEY'],
    groupId: 'credentials',
  ),
  SettingsSearchEntry(
    title: 'Quota Credential Environment',
    description:
        'Configure environment variable names for Kimi, Z.ai and MiniMax.',
    keywords: <String>[
      'environment',
      'api key',
      'kimi',
      'z.ai',
      'minimax',
      'remote',
      'host',
    ],
    groupId: 'credentials',
  ),
];

const List<SettingsSearchEntry> keyboardSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Keyboard Shortcuts',
    description: 'View and remap app-wide key bindings.',
    keywords: <String>['shortcut', 'hotkey', 'keybinding', 'binding', 'keymap'],
  ),
  SettingsSearchEntry(
    title: 'Terminal Shortcut Behavior',
    description:
        'Choose whether app shortcuts win while a terminal is '
        'focused.',
    keywords: <String>['app first', 'terminal first', 'policy'],
  ),
];

const List<SettingsSearchEntry> browserSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'System Browser Engine',
    description: 'Check the stable browser capability gate.',
    keywords: <String>['browser', 'webview', 'webkit', 'webview2', 'engine'],
    groupId: 'general',
  ),
  SettingsSearchEntry(
    title: 'Browser Search Engine',
    description: 'Choose the default address bar search provider.',
    keywords: <String>['google', 'duckduckgo', 'bing', 'kagi', 'search'],
    groupId: 'general',
  ),
  SettingsSearchEntry(
    title: 'Browser Profiles',
    description: 'Manage isolated cookies, storage and permissions.',
    keywords: <String>['browser', 'profile', 'cookies', 'storage', 'import'],
    groupId: 'profiles',
  ),
  SettingsSearchEntry(
    title: 'Trusted Local Certificates',
    description: 'Review or remove certificate trust for browser profiles.',
    keywords: <String>[
      'browser',
      'certificate',
      'tls',
      'https',
      'localhost',
      'self signed',
    ],
    groupId: 'certificates',
  ),
  SettingsSearchEntry(
    title: 'Browser History',
    description: 'Clear history and reopen recently closed tabs.',
    keywords: <String>['browser', 'history', 'closed', 'tabs'],
    groupId: 'data',
  ),
];

const List<SettingsSearchEntry> editorSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Theme Preset',
    description: 'Syntax highlighting theme used by editor tabs.',
    keywords: <String>['syntax', 'highlight', 'highlighting', 'color', 'code'],
  ),
  SettingsSearchEntry(
    title: 'Tab Size',
    description: 'Spaces inserted when pressing tab in editor tabs.',
    keywords: <String>['indent', 'indentation', 'spaces', 'code'],
  ),
  SettingsSearchEntry(
    title: 'Autosave',
    description: 'Automatically save dirty editor tabs after a pause.',
    keywords: <String>['save', 'automatic', 'idle', 'file', 'changes'],
  ),
  SettingsSearchEntry(
    title: 'Autosave Delay',
    description: 'Idle time before saving editor changes.',
    keywords: <String>['save', 'automatic', 'debounce', 'seconds'],
  ),
];

const List<SettingsSearchEntry> aiTextSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'AI Text Generation',
    description: 'Generate source control text with local agent CLIs.',
    keywords: <String>['ai', 'commit', 'pull request', 'branch'],
    groupId: 'generation',
  ),
  SettingsSearchEntry(
    title: 'AI Text Agent',
    description: 'Choose the CLI used for generated text.',
    keywords: <String>[
      'codex',
      'claude',
      'copilot',
      'cursor',
      'antigravity',
      'agy',
      'opencode',
      'opencode2',
      'pi',
      'amp',
      'custom',
    ],
    groupId: 'generation',
  ),
  SettingsSearchEntry(
    title: 'AI Text Commit Messages',
    description:
        'Choose the agent, model, reasoning and instructions for commit messages.',
    keywords: <String>[
      'prompt',
      'instructions',
      'commit message',
      'agent',
      'model',
      'reasoning',
      'override',
      'inherit',
    ],
    groupId: 'commitMessage',
  ),
  SettingsSearchEntry(
    title: 'AI Text Pull Request Details',
    description:
        'Choose the agent, model, reasoning and instructions for pull request details.',
    keywords: <String>[
      'prompt',
      'instructions',
      'agent',
      'model',
      'reasoning',
      'inherit',
      'override',
      'pull request',
      'pr',
    ],
    groupId: 'pullRequestDetails',
  ),
  ...readingDiffSearchEntries,
  SettingsSearchEntry(
    title: 'AI Text Workspace Identity',
    description:
        'Choose the agent, model, reasoning and instructions for workspace identity.',
    keywords: <String>[
      'prompt',
      'instructions',
      'agent',
      'model',
      'reasoning',
      'inherit',
      'override',
      'workspace identity',
    ],
    groupId: 'workspaceIdentity',
  ),
];
