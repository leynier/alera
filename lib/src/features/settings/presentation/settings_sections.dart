import 'package:flutter/material.dart';

/// Sidebar grouping for settings sections: plain preferences vs entity
/// management (master-detail CRUD) panes.
enum SettingsNavGroup(final String label) {
  preferences('Preferences'),
  resources('Resources'),
}

/// A titled group of rows inside a section pane, addressable for subsection
/// navigation chips and search jumps.
class const SettingsGroupSpec({
  required final String id,
  required final String title,
});

class const SettingsSectionData({
  required final String id,
  required final String title,
  required final String description,
  required final IconData icon,
  required final List<SettingsSearchEntry> entries,
  required final WidgetBuilder builder,
  final SettingsNavGroup navGroup = SettingsNavGroup.preferences,
  final List<SettingsGroupSpec> groups = const <SettingsGroupSpec>[],
  final Future<void> Function()? onReset,
}) {
  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    final sectionEntry = SettingsSearchEntry(
      title: title,
      description: description,
    );
    return sectionEntry.matches(query) ||
        entries.any((entry) => entry.matches(query));
  }

  int matchCount(String query) {
    if (query.isEmpty) {
      return 0;
    }
    return entries.where((entry) => entry.matches(query)).length;
  }

  /// Id of the first group with an entry matching [query], for search jumps.
  String? firstMatchingGroupId(String query) {
    if (query.isEmpty) {
      return null;
    }
    for (final entry in entries) {
      if (entry.groupId != null && entry.matches(query)) {
        return entry.groupId;
      }
    }
    return null;
  }
}

class const SettingsSearchEntry({
  required final String title,
  final String? description,
  final List<String> keywords = const <String>[],
  this.groupId,
}) {
  /// [SettingsGroupSpec.id] of the pane group holding this setting, when the
  /// section supports subsection navigation.
  final String? groupId;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return <String>[
      title,
      description ?? '',
      ...keywords,
    ].any((value) => value.toLowerCase().contains(query));
  }
}
