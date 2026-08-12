import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry>
aiDictationSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'AI Dictation',
    description: 'Transcribe microphone recordings locally with Whisper.',
    keywords: <String>[
      'ai',
      'dictation',
      'voice',
      'speech',
      'whisper',
      'microphone',
    ],
    groupId: 'local',
  ),
  SettingsSearchEntry(
    title: 'Whisper Model',
    description: 'Download or remove the offline Whisper base model.',
    keywords: <String>['offline', 'model', 'download', 'privacy'],
    groupId: 'local',
  ),
  SettingsSearchEntry(
    title: 'Dictation Fallbacks',
    description: 'Configure runtime and OpenAI-compatible speech providers.',
    keywords: <String>['remote', 'runtime', 'provider', 'openai', 'fallback'],
    groupId: 'fallback',
  ),
];
