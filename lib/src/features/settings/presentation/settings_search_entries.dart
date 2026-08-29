import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_reading_diff.dart';

final List<SettingsSearchEntry>
applicationSearchEntries = buildSettingsSearchEntryCatalog(const {
  'storage': {
    'Workspace Directory': SettingsSearchEntryDetails(
      description: 'Where new linked workspaces are created on disk.',
      keywords: <String>['worktree', 'folder', 'location', 'path'],
    ),
  },
  'safety': {
    'Confirm Project Removal': SettingsSearchEntryDetails(
      description: 'Ask before unregistering a project.',
      keywords: <String>['safety', 'destructive', 'remove', 'delete'],
    ),
    'Confirm Workspace Removal': SettingsSearchEntryDetails(
      description: 'Ask before removing a workspace worktree.',
      keywords: <String>['safety', 'destructive', 'remove', 'delete'],
    ),
  },
  'desktop': {
    'Show Tray Icon': SettingsSearchEntryDetails(
      description:
          'Keep Alera in the menu extra, notification area, or Ubuntu status bar.',
      keywords: <String>[
        'tray',
        'status bar',
        'menu extra',
        'notification area',
        'appindicator',
        'hide',
        'close',
      ],
    ),
    'Show Dock Badge': SettingsSearchEntryDetails(
      description:
          'Show how many agents are waiting for review on the Dock or taskbar.',
      keywords: <String>[
        'dock',
        'taskbar',
        'badge',
        'count',
        'attention',
        'review',
        'ubuntu',
      ],
    ),
    'Show Tray Badge': SettingsSearchEntryDetails(
      description:
          'Draw how many agents are waiting for review onto the tray icon.',
      keywords: <String>[
        'tray',
        'badge',
        'count',
        'number',
        'attention',
        'review',
        'status bar',
        'linux',
      ],
    ),
  },
  'runtime': {
    'Keep Computer Awake': SettingsSearchEntryDetails(
      description:
          'Prevent idle sleep and display sleep while Alera is running.',
      keywords: <String>[
        'keep-alive',
        'awake',
        'sleep',
        'caffeinate',
        'display',
        'idle',
        'power',
      ],
    ),
    'Keep Runtime Open When App Quits': SettingsSearchEntryDetails(
      description: 'Leave the app-launched sidecar running after a clean quit.',
      keywords: <String>[
        'host',
        'sidecar',
        'lifecycle',
        'quit',
        'shutdown',
        'leave',
      ],
    ),
    'Empty Host Shutdown': SettingsSearchEntryDetails(
      description:
          'Stop the terminal host after the app closes with no sessions.',
      keywords: <String>['host', 'sidecar', 'lifetime', 'timeout'],
    ),
    'Detached Session Shutdown': SettingsSearchEntryDetails(
      description:
          'Stop detached running terminal sessions after the app stays closed.',
      keywords: <String>['host', 'sidecar', 'session', 'timeout'],
    ),
  },
  'diagnostics': {
    'Open Logs Folder': SettingsSearchEntryDetails(
      description: 'Show the folder holding the app log files.',
      keywords: <String>['log', 'logs', 'diagnostics', 'debug', 'folder'],
    ),
    'Export Diagnostics': SettingsSearchEntryDetails(
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
    ),
    'Log Level': SettingsSearchEntryDetails(
      description: 'How much detail is written to the log files.',
      keywords: <String>['log', 'verbose', 'debug', 'diagnostics'],
    ),
    'Send Crash Reports': SettingsSearchEntryDetails(
      description: 'Send crashes to Sentry, an external service.',
      keywords: <String>['crash', 'sentry', 'telemetry', 'report', 'error'],
    ),
  },
  'updates': {
    'Updates': SettingsSearchEntryDetails(
      description: 'Check desktop releases for this platform.',
      keywords: <String>['release', 'download', 'version'],
    ),
  },
  'support': {
    'Star Alera on GitHub': SettingsSearchEntryDetails(
      description: 'Show your support for the project.',
      keywords: <String>['support', 'github', 'star'],
    ),
  },
});

final List<SettingsSearchEntry>
agentsSearchEntries = buildSettingsSearchEntryCatalog(const {
  'cliSkill': {
    'All Alera Skills': SettingsSearchEntryDetails(
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
    ),
    'Alera CLI Skill': SettingsSearchEntryDetails(
      description: 'Install agent instructions for the Alera CLI.',
      keywords: <String>['codex', 'skill', 'cli', 'agent', 'workspace'],
    ),
    'Agent Canvas Skill': SettingsSearchEntryDetails(
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
    ),
    'Alera Orchestration Skill': SettingsSearchEntryDetails(
      description: 'Install agent instructions for Alera orchestration.',
      keywords: <String>[
        'orchestration',
        'skill',
        'agent',
        'handoff',
        'task',
        'dispatch',
      ],
    ),
    'Alera Computer Use Skill': SettingsSearchEntryDetails(
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
    ),
  },
  'hooks': {
    'Codex Hooks': SettingsSearchEntryDetails(
      description: 'Use Alera-managed Codex runtime hooks.',
      keywords: <String>['codex', 'agent', 'status', 'hooks'],
    ),
    'Claude Code Hooks': SettingsSearchEntryDetails(
      description: 'Use an Alera-managed Claude Code config with status hooks.',
      keywords: <String>['claude', 'agent', 'status', 'hooks'],
    ),
    'GitHub Copilot Hooks': SettingsSearchEntryDetails(
      description: 'Use an Alera-managed GitHub Copilot home overlay.',
      keywords: <String>['copilot', 'github', 'agent', 'status', 'hooks'],
    ),
    'Cursor Hooks': SettingsSearchEntryDetails(
      description: 'Use an Alera-managed Cursor agent plugin wrapper.',
      keywords: <String>['cursor', 'agent', 'status', 'hooks', 'cli'],
    ),
    'Antigravity Hooks': SettingsSearchEntryDetails(
      description: 'Install managed Antigravity hooks for the agy CLI.',
      keywords: <String>['antigravity', 'agy', 'agent', 'status', 'hooks'],
    ),
    'OpenCode Hooks': SettingsSearchEntryDetails(
      description: 'Install managed OpenCode status plugin.',
      keywords: <String>['opencode', 'agent', 'status', 'hooks', 'plugin'],
    ),
    'OpenCode 2 Hooks': SettingsSearchEntryDetails(
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
    ),
    'Pi Hooks': SettingsSearchEntryDetails(
      description: 'Install managed Pi status extension.',
      keywords: <String>['pi', 'agent', 'status', 'hooks', 'extension'],
    ),
    'Amp Hooks': SettingsSearchEntryDetails(
      description: 'Use an Alera-managed Amp config overlay.',
      keywords: <String>['amp', 'agent', 'status', 'hooks', 'plugin'],
    ),
    'Grok Build Hooks': SettingsSearchEntryDetails(
      description: 'Install managed Grok Build status hooks.',
      keywords: <String>['grok', 'xai', 'agent', 'status', 'hooks'],
    ),
  },
  'behavior': {
    'Agent Status Notifications': SettingsSearchEntryDetails(
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
    ),
    'Agent Finished Notifications': SettingsSearchEntryDetails(
      description: 'Also notify when an agent finishes a turn.',
      keywords: <String>[
        'agent',
        'status',
        'notification',
        'finished',
        'done',
        'turn',
      ],
    ),
    'Keep Computer Awake While Agents Are Working': SettingsSearchEntryDetails(
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
    ),
  },
});

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

final List<SettingsSearchEntry>
browserSearchEntries = buildSettingsSearchEntryCatalog(const {
  'general': {
    'System Browser Engine': SettingsSearchEntryDetails(
      description: 'Check the stable browser capability gate.',
      keywords: <String>['browser', 'webview', 'webkit', 'webview2', 'engine'],
    ),
    'Browser Search Engine': SettingsSearchEntryDetails(
      description: 'Choose the default address bar search provider.',
      keywords: <String>['google', 'duckduckgo', 'bing', 'kagi', 'search'],
    ),
  },
  'profiles': {
    'Browser Profiles': SettingsSearchEntryDetails(
      description: 'Manage isolated cookies, storage and permissions.',
      keywords: <String>['browser', 'profile', 'cookies', 'storage', 'import'],
    ),
  },
  'certificates': {
    'Trusted Local Certificates': SettingsSearchEntryDetails(
      description: 'Review or remove certificate trust for browser profiles.',
      keywords: <String>[
        'browser',
        'certificate',
        'tls',
        'https',
        'localhost',
        'self signed',
      ],
    ),
  },
  'data': {
    'Browser History': SettingsSearchEntryDetails(
      description: 'Clear history and reopen recently closed tabs.',
      keywords: <String>['browser', 'history', 'closed', 'tabs'],
    ),
  },
});

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

const List<SettingsSearchEntry> aiAssistSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'AI Assist',
    description:
        'Run short local agent jobs for source control, workspace identity, and speech.',
    keywords: <String>['ai', 'assist', 'commit', 'pull request', 'branch'],
    groupId: 'generation',
  ),
  SettingsSearchEntry(
    title: 'AI Assist Agent',
    description: 'Choose the CLI used for AI Assist jobs.',
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
    title: 'AI Assist Commit Messages',
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
    title: 'AI Assist Pull Request Details',
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
    title: 'AI Assist Workspace Identity',
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
