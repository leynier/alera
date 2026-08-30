import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final class const SettingsSearchEntryDetails({
  final String? description,
  final List<String> keywords = const <String>[],
});

List<SettingsSearchEntry> buildSettingsSearchEntryCatalog(
  Map<String, Map<String, SettingsSearchEntryDetails>> groups,
) {
  return List<SettingsSearchEntry>.unmodifiableOf(<SettingsSearchEntry>[
    for (final group in groups.entries)
      for (final entry in group.value.entries)
        SettingsSearchEntry(
          title: entry.key,
          description: entry.value.description,
          keywords: entry.value.keywords,
          groupId: group.key,
        ),
  ]);
}
