import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final List<SettingsSearchEntry>
aiDictationSearchEntries = buildSettingsSearchEntryCatalog(const {
  'transcription': {
    'AI Dictation': SettingsSearchEntryDetails(
      description: 'Transcribe microphone recordings locally with Whisper.',
      keywords: <String>[
        'ai',
        'dictation',
        'voice',
        'speech',
        'whisper',
        'microphone',
      ],
    ),
  },
  'models': {
    'Whisper Model': SettingsSearchEntryDetails(
      description: 'Download, resume, select, or remove local Whisper models.',
      keywords: <String>['offline', 'model', 'download', 'resume', 'privacy'],
    ),
  },
  'processing': {
    'Speech Processing': SettingsSearchEntryDetails(
      description:
          'Clean up or summarize transcripts with an agent subscription.',
      keywords: <String>['agent', 'model', 'summary', 'cleanup', 'speech'],
    ),
  },
});
