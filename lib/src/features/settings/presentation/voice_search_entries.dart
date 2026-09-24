import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final List<SettingsSearchEntry>
voiceSearchEntries = buildSettingsSearchEntryCatalog(const {
  'pipeline': {
    'Voice Pipeline': SettingsSearchEntryDetails(
      description:
          'Choose chained STT and TTS or a realtime speech-to-speech model.',
      keywords: <String>['voice', 'realtime', 'gemini', 'whisper', 'tts'],
    ),
  },
  'speech': {
    'Speech Providers': SettingsSearchEntryDetails(
      description: 'Pick STT, TTS, or a realtime provider independently.',
      keywords: <String>['stt', 'tts', 'openai', 'gemini live'],
    ),
  },
  'home': {
    'Home Agent': SettingsSearchEntryDetails(
      description: 'The CLI profile that thinks and delegates from voice.',
      keywords: <String>['codex', 'grok', 'home', 'orchestrator'],
    ),
  },
});
