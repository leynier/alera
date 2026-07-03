import 'package:flutter/material.dart';

class SettingsSectionData {
  const SettingsSectionData({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.entries,
    required this.builder,
    this.onReset,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<SettingsSearchEntry> entries;
  final WidgetBuilder builder;
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
}

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    this.description,
    this.keywords = const <String>[],
  });

  final String title;
  final String? description;
  final List<String> keywords;

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
