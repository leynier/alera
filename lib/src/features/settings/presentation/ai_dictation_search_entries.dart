import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final List<SettingsSearchEntry>
aiDictationSearchEntries = buildSettingsSearchEntryCatalog(const {
  'transcription': {
    'AI Dictation': SettingsSearchEntryDetails(
      description:
          'Transcribe microphone recordings locally or with a remote speech API.',
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
  'remote': {
    'Remote Transcription': SettingsSearchEntryDetails(
      description:
          'Use a Codex subscription or an OpenAI-compatible API with a secure token.',
      keywords: <String>['codex', 'openai', 'api', 'token', 'url', 'remote'],
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
  'test': {
    'Test AI Dictation': SettingsSearchEntryDetails(
      description:
          'Record and transcribe a sample without leaving AI Dictation settings.',
      keywords: <String>['test', 'record', 'microphone', 'transcript'],
    ),
  },
});
