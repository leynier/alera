import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry> aiDictationSearchEntries =
    <SettingsSearchEntry>[
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
        groupId: 'transcription',
      ),
      SettingsSearchEntry(
        title: 'Whisper Model',
        description:
            'Download, resume, select, or remove local Whisper models.',
        keywords: <String>['offline', 'model', 'download', 'resume', 'privacy'],
        groupId: 'models',
      ),
      SettingsSearchEntry(
        title: 'Speech Processing',
        description:
            'Clean up or summarize transcripts with an agent subscription.',
        keywords: <String>['agent', 'model', 'summary', 'cleanup', 'speech'],
        groupId: 'processing',
      ),
    ];
