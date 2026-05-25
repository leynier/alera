import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';

/// User customization of keyboard shortcuts.
///
/// [overrides] maps an action to the canonical chord strings the user assigned.
/// Three states are encoded:
/// - absent key: use the registry default for the action,
/// - present with a non-empty list: use those chords,
/// - present with an empty list: the action is explicitly disabled.
class KeyboardShortcutSettings {
  const KeyboardShortcutSettings({
    this.overrides = const <KeyboardActionId, List<String>>{},
    this.terminalPolicy = TerminalShortcutPolicy.appFirst,
  });

  final Map<KeyboardActionId, List<String>> overrides;
  final TerminalShortcutPolicy terminalPolicy;

  static const KeyboardShortcutSettings defaults = KeyboardShortcutSettings();

  bool hasOverride(KeyboardActionId id) => overrides.containsKey(id);

  bool isDisabled(KeyboardActionId id) => overrides[id]?.isEmpty ?? false;

  /// Returns a copy with [chords] applied to [id]. A null [chords] removes the
  /// override (restoring the default); an empty list disables the action.
  KeyboardShortcutSettings copyWithOverride(
    KeyboardActionId id,
    List<String>? chords,
  ) {
    final next = Map<KeyboardActionId, List<String>>.from(overrides);
    if (chords == null) {
      next.remove(id);
    } else {
      next[id] = List<String>.unmodifiable(chords);
    }
    return KeyboardShortcutSettings(
      overrides: Map<KeyboardActionId, List<String>>.unmodifiable(next),
      terminalPolicy: terminalPolicy,
    );
  }

  KeyboardShortcutSettings copyWithPolicy(TerminalShortcutPolicy policy) {
    return KeyboardShortcutSettings(
      overrides: overrides,
      terminalPolicy: policy,
    );
  }

  KeyboardShortcutSettings cleared() {
    return KeyboardShortcutSettings(terminalPolicy: terminalPolicy);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'terminalPolicy': terminalPolicy.name,
      'overrides': <String, Object?>{
        for (final entry in overrides.entries) entry.key.name: entry.value,
      },
    };
  }

  factory KeyboardShortcutSettings.fromJson(Map<String, Object?> json) {
    return KeyboardShortcutSettings(
      overrides: _overridesFromWire(json['overrides']),
      terminalPolicy: _policyFromWire(json['terminalPolicy']),
    );
  }
}

TerminalShortcutPolicy _policyFromWire(Object? value) {
  if (value is String) {
    for (final policy in TerminalShortcutPolicy.values) {
      if (policy.name == value) {
        return policy;
      }
    }
  }
  return TerminalShortcutPolicy.appFirst;
}

/// Parses persisted overrides, dropping unknown actions and chords that no
/// longer parse so a corrupt or stale record degrades gracefully to defaults.
Map<KeyboardActionId, List<String>> _overridesFromWire(Object? value) {
  if (value is! Map) {
    return const <KeyboardActionId, List<String>>{};
  }
  final actionsByName = <String, KeyboardActionId>{
    for (final id in KeyboardActionId.values) id.name: id,
  };
  final result = <KeyboardActionId, List<String>>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final id = key is String ? actionsByName[key] : null;
    if (id == null) {
      continue;
    }
    final rawChords = entry.value;
    if (rawChords is! List) {
      continue;
    }
    final chords = <String>[];
    for (final raw in rawChords) {
      if (raw is! String) {
        continue;
      }
      final parsed = KeyChord.parse(raw);
      if (parsed is KeyChordParseSuccess) {
        final canonical = parsed.chord.toCanonicalString();
        if (!chords.contains(canonical)) {
          chords.add(canonical);
        }
      }
    }
    // An empty list is meaningful (disabled); only skip when the raw value was
    // not a list at all (handled above).
    result[id] = List<String>.unmodifiable(chords);
  }
  return Map<KeyboardActionId, List<String>>.unmodifiable(result);
}
