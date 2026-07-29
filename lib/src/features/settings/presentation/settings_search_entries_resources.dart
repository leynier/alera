import 'package:alera/src/features/settings/presentation/settings_sections.dart';

// Search entries for the Resources nav group: the master-detail panes that
// manage declared entities rather than plain preferences.

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

const List<SettingsSearchEntry> agentProfileSearchEntries =
    <SettingsSearchEntry>[
      SettingsSearchEntry(
        title: 'Agent Profiles',
        description:
            'Declare the agents and launch commands orchestration may '
            'dispatch to.',
        keywords: <String>[
          'agent',
          'profile',
          'catalog',
          'orchestration',
          'adapter',
          'command',
          'model',
          'quota group',
          'fallback',
        ],
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
        description: 'Rename, Revoke, Or Delete Paired Mobile Devices.',
        keywords: <String>['revoke', 'rename', 'delete', 'device', 'token'],
        groupId: 'devices',
      ),
    ];
