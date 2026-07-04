import 'package:flutter/material.dart';

/// Sidebar grouping for settings sections: plain preferences vs entity
/// management (master-detail CRUD) panes.
enum SettingsNavGroup {
  preferences('Preferences'),
  resources('Resources');

  const SettingsNavGroup(this.label);

  final String label;
}

/// A titled group of rows inside a section pane, addressable for subsection
/// navigation chips and search jumps.
class SettingsGroupSpec {
  const SettingsGroupSpec({required this.id, required this.title});

  final String id;
  final String title;
}

class SettingsSectionData {
  const SettingsSectionData({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.entries,
    required this.builder,
    this.navGroup = SettingsNavGroup.preferences,
    this.groups = const <SettingsGroupSpec>[],
    this.onReset,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<SettingsSearchEntry> entries;
  final WidgetBuilder builder;
  final SettingsNavGroup navGroup;
  final List<SettingsGroupSpec> groups;
  final Future<void> Function()? onReset;

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

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    this.description,
    this.keywords = const <String>[],
    this.groupId,
  });

  final String title;
  final String? description;
  final List<String> keywords;

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
