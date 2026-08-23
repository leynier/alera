import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final class SettingsSearchEntryDetails {
  const SettingsSearchEntryDetails({
    this.description,
    this.keywords = const <String>[],
  });

  final String? description;
  final List<String> keywords;
}

List<SettingsSearchEntry> buildSettingsSearchEntryCatalog(
  Map<String, Map<String, SettingsSearchEntryDetails>> groups,
) {
  return List<SettingsSearchEntry>.unmodifiable(<SettingsSearchEntry>[
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
