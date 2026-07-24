import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry> applicationSearchEntries =
    <SettingsSearchEntry>[
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
        title: 'Stop Runtime When App Quits',
        description: 'Shut down the local runtime when the last window closes.',
        keywords: <String>['host', 'sidecar', 'lifecycle', 'quit', 'shutdown'],
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
    title: 'Alera CLI Skill',
    description: 'Install agent instructions for the Alera CLI.',
    keywords: <String>['codex', 'skill', 'cli', 'agent', 'workspace'],
    groupId: 'cliSkill',
  ),
  SettingsSearchEntry(
    title: 'Alera Orchestration Skill',
    description: 'Install Agent Instructions For Alera Orchestration.',
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
    description: 'Use an Alera-managed Cursor Agent plugin wrapper.',
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
    description: 'Choose Quota Providers And Their Display Order.',
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
    ],
    groupId: 'providers',
  ),
  SettingsSearchEntry(
    title: 'Claude Code Quotas',
    description: 'Enable Claude Quotas For Default And CCS Accounts.',
    keywords: <String>['claude', 'quota', 'usage'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude Default Quotas',
    description: 'Configure The Default Claude Account Independently.',
    keywords: <String>['claude', 'default', 'account', 'quota'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude CCS Profiles',
    description: 'Configure CCS Alias And Profile Pairs For Claude Quotas.',
    keywords: <String>['claude', 'ccs', 'profile', 'alias', 'quota'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Kimi API Key Variable',
    description: 'Configure The Kimi API Key Environment Variable Name.',
    keywords: <String>['kimi', 'environment', 'api key', 'KIMI_API_KEY'],
    groupId: 'credentials',
  ),
  SettingsSearchEntry(
    title: 'Quota Credential Environment',
    description:
        'Configure Environment Variable Names For Kimi, Z.ai And MiniMax.',
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

const List<SettingsSearchEntry> projectSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Project Worktree Setup',
    description: 'Copy Files And Run Setup Commands For Linked Workspaces.',
    keywords: <String>[
      'project',
      'repo',
      'worktree',
      'workspace',
      'copy',
      'setup',
      'alera.toml',
    ],
  ),
];

const List<SettingsSearchEntry> remoteHostSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Remote Hosts',
    description: 'Manage SSH targets and remote runtime bootstrap.',
    keywords: <String>['ssh', 'remote', 'host', 'runtime', 'bootstrap'],
  ),
];

const List<SettingsSearchEntry> mobileDeviceSearchEntries =
    <SettingsSearchEntry>[
      SettingsSearchEntry(
        title: 'Mobile Gateway',
        description: 'Enable And Configure The Mobile Companion Gateway.',
        keywords: <String>[
          'mobile',
          'gateway',
          'bind',
          'port',
          'enable',
          'wss',
          'endpoint',
          'tailscale',
          'tailnet',
          'vpn',
          'remote',
        ],
        groupId: 'gateway',
      ),
      SettingsSearchEntry(
        title: 'Link Mobile Device',
        description: 'Generate A Pairing QR For The Mobile Companion App.',
        keywords: <String>[
          'qr',
          'pair',
          'pairing',
          'scan',
          'phone',
          'companion',
          'link',
        ],
        groupId: 'pairing',
      ),
      SettingsSearchEntry(
        title: 'Paired Devices',
        description: 'Rename Or Revoke Paired Mobile Devices.',
        keywords: <String>['revoke', 'rename', 'device', 'token'],
        groupId: 'devices',
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

const List<SettingsSearchEntry> editorSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Theme Preset',
    description: 'Syntax highlighting theme used by editor tabs.',
    keywords: <String>['syntax', 'highlight', 'highlighting', 'color', 'code'],
  ),
  SettingsSearchEntry(
    title: 'Tab Size',
    description: 'Spaces inserted when pressing Tab in editor tabs.',
    keywords: <String>['indent', 'indentation', 'spaces', 'code'],
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
      'pi',
      'amp',
      'custom',
    ],
    groupId: 'generation',
  ),
  SettingsSearchEntry(
    title: 'AI Text Instructions',
    description: 'Commit and pull request instructions for generated text.',
    keywords: <String>[
      'prompt',
      'instructions',
      'commit message',
      'pull request',
      'pr',
    ],
    groupId: 'instructions',
  ),
];

const List<SettingsSearchEntry> terminalSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Font Family',
    description: 'Typeface used in new terminal sessions.',
    keywords: <String>['monospace', 'jetbrains', 'typeface'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Font Size',
    description: 'Text size used in new terminal sessions.',
    keywords: <String>['terminal text', 'zoom'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Font Weight',
    description: 'Weight used for terminal text.',
    keywords: <String>['terminal text', 'bold'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Line Height',
    description: 'Vertical spacing for terminal rows.',
    keywords: <String>['spacing', 'rows'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Theme Preset',
    description: 'Built-in terminal color theme.',
    keywords: <String>['color', 'appearance', 'palette'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Background Opacity',
    description: 'Opacity of the terminal background.',
    keywords: <String>['transparent', 'alpha'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Horizontal Padding',
    description: 'Horizontal spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Vertical Padding',
    description: 'Vertical spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Cursor Shape',
    description: 'Cursor style for new terminal sessions.',
    keywords: <String>['caret', 'block', 'bar', 'underline'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Blinking Cursor',
    description: 'Blink the terminal cursor while focused.',
    keywords: <String>['caret', 'blink'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Cursor Opacity',
    description: 'Opacity of the terminal cursor.',
    keywords: <String>['caret', 'alpha'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Color Overrides',
    description: 'Override core terminal colors.',
    keywords: <String>['foreground', 'background', 'selection', 'cursor'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'TUI Scroll Speed',
    description: 'Mouse wheel speed for interactive terminal applications.',
    keywords: <String>['mouse', 'wheel', 'opencode', 'amp', 'claude'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Copy On Select',
    description: 'Copy local terminal selections automatically.',
    keywords: <String>['clipboard', 'selection', 'mouse'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Allow OSC 52 Clipboard Writes',
    description: 'Allow terminal applications to replace the clipboard.',
    keywords: <String>['clipboard', 'tui', 'ssh', 'tmux', 'osc52'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Scrollback Lines',
    description: 'Maximum terminal history retained per session.',
    keywords: <String>['history', 'buffer'],
    groupId: 'advanced',
  ),
  SettingsSearchEntry(
    title: 'Host Scrollback Size',
    description: 'Maximum host-side terminal output retained per session.',
    keywords: <String>['history', 'buffer', 'memory', 'host'],
    groupId: 'advanced',
  ),
  SettingsSearchEntry(
    title: 'Word Separators',
    description: 'Characters that break double-click word selection.',
    keywords: <String>['boundary', 'selection', 'double click'],
    groupId: 'advanced',
  ),
];
