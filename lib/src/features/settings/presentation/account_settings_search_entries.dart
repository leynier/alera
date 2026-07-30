import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry> accountSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Alera Account',
    description: 'Sign in with Google or GitHub.',
    keywords: <String>['identity', 'login', 'sign in', 'google', 'github'],
    groupId: 'identity',
  ),
  SettingsSearchEntry(
    title: 'Mobile Push',
    description: 'Choose which runtime events notify enrolled phones.',
    keywords: <String>[
      'firebase',
      'fcm',
      'notification',
      'waiting',
      'blocked',
      'done',
      'terminal',
    ],
    groupId: 'push',
  ),
  SettingsSearchEntry(
    title: 'Account Ownership',
    description: 'Transfer a runtime or delete an Alera account.',
    keywords: <String>['move', 'transfer', 'delete', 'privacy'],
    groupId: 'ownership',
  ),
];
