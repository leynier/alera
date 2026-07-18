import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_shortcut_builder.dart';

const int terminalAccessoryLayoutVersion = 1;

/// A user-defined quick key: one special key or printable character plus
/// modifiers, rendered through the shortcut builder.
class TerminalCustomKey {
  const TerminalCustomKey({
    required this.id,
    required this.key,
    required this.modifiers,
  });

  final String id;
  final String key;
  final Set<TerminalShortcutModifier> modifiers;

  TerminalShortcutBuildResult? build() {
    return buildTerminalShortcutKey(
      TerminalShortcutBinding(key: key, modifiers: modifiers),
    );
  }

  factory TerminalCustomKey.fromJson(Map<String, Object?> json) {
    return TerminalCustomKey(
      id: json.requiredString('id'),
      key: json.requiredString('key'),
      modifiers: <TerminalShortcutModifier>{
        for (final name in json.stringList('modifiers'))
          for (final modifier in TerminalShortcutModifier.values)
            if (modifier.name == name) modifier,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'key': key,
      'modifiers': <String>[
        for (final modifier in TerminalShortcutModifier.values)
          if (modifiers.contains(modifier)) modifier.name,
      ],
    };
  }
}

/// Persisted ordering, visibility, and custom keys for the accessory bar.
/// Unknown ids are dropped at load time; built-ins added in newer app
/// versions merge in next to their canonical neighbors.
class TerminalAccessoryLayout {
  const TerminalAccessoryLayout({
    required this.orderedIds,
    required this.hiddenIds,
    required this.customKeys,
  });

  final List<String> orderedIds;
  final Set<String> hiddenIds;
  final List<TerminalCustomKey> customKeys;

  static TerminalAccessoryLayout defaults() {
    return TerminalAccessoryLayout(
      orderedIds: <String>[
        for (final key in builtInTerminalAccessoryKeys) key.id,
      ],
      hiddenIds: const <String>{},
      customKeys: const <TerminalCustomKey>[],
    );
  }

  factory TerminalAccessoryLayout.fromJson(Map<String, Object?> json) {
    final customKeys = <TerminalCustomKey>[
      for (final item in json.objectList('customKeys'))
        if (item is Map) TerminalCustomKey.fromJson(asJsonMap(item)),
    ];
    final knownIds = <String>{
      ...builtInTerminalAccessoryKeysById.keys,
      for (final custom in customKeys) custom.id,
    };
    final orderedIds = <String>[
      for (final id in json.stringList('orderedIds'))
        if (knownIds.contains(id)) id,
    ];
    return TerminalAccessoryLayout(
      orderedIds: mergeMissingBuiltInIds(orderedIds),
      hiddenIds: <String>{
        for (final id in json.stringList('hiddenIds'))
          if (knownIds.contains(id)) id,
      },
      customKeys: customKeys,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': terminalAccessoryLayoutVersion,
      'orderedIds': orderedIds,
      'hiddenIds': hiddenIds.toList(),
      'customKeys': <Object?>[for (final custom in customKeys) custom.toJson()],
    };
  }

  TerminalAccessoryLayout copyWith({
    List<String>? orderedIds,
    Set<String>? hiddenIds,
    List<TerminalCustomKey>? customKeys,
  }) {
    return TerminalAccessoryLayout(
      orderedIds: orderedIds ?? this.orderedIds,
      hiddenIds: hiddenIds ?? this.hiddenIds,
      customKeys: customKeys ?? this.customKeys,
    );
  }

  /// All keys in user order (hidden included), custom keys resolved through
  /// the shortcut builder. Custom keys with unbuildable bindings are skipped.
  List<TerminalAccessoryKey> orderedKeys() {
    final customById = <String, TerminalCustomKey>{
      for (final custom in customKeys) custom.id: custom,
    };
    final out = <TerminalAccessoryKey>[];
    final seen = <String>{};
    for (final id in orderedIds) {
      if (!seen.add(id)) {
        continue;
      }
      final builtIn = builtInTerminalAccessoryKeysById[id];
      if (builtIn != null) {
        out.add(builtIn);
        continue;
      }
      final resolved = customById[id]?.build();
      if (resolved != null) {
        out.add(
          TerminalAccessoryKey(
            id: id,
            label: resolved.label,
            bytes: resolved.bytes,
            accessibilityLabel: resolved.accessibilityLabel,
          ),
        );
      }
    }
    for (final custom in customKeys) {
      if (seen.add(custom.id)) {
        final resolved = custom.build();
        if (resolved != null) {
          out.add(
            TerminalAccessoryKey(
              id: custom.id,
              label: resolved.label,
              bytes: resolved.bytes,
              accessibilityLabel: resolved.accessibilityLabel,
            ),
          );
        }
      }
    }
    return out;
  }

  /// The keys actually rendered on the bar.
  List<TerminalAccessoryKey> visibleKeys() {
    return <TerminalAccessoryKey>[
      for (final key in orderedKeys())
        if (!hiddenIds.contains(key.id)) key,
    ];
  }
}

/// Ports Orca's `insertMissingBuiltInIds`: a built-in missing from the saved
/// order (added in a newer app version) is inserted right after its nearest
/// preceding canonical neighbor that the user already has, so it lands where
/// users expect instead of at the end.
List<String> mergeMissingBuiltInIds(List<String> savedOrder) {
  final result = List<String>.of(savedOrder);
  final canonical = <String>[
    for (final key in builtInTerminalAccessoryKeys) key.id,
  ];
  for (var i = 0; i < canonical.length; i++) {
    final id = canonical[i];
    if (result.contains(id)) {
      continue;
    }
    var insertAt = 0;
    for (var j = i - 1; j >= 0; j--) {
      final neighborIndex = result.indexOf(canonical[j]);
      if (neighborIndex >= 0) {
        insertAt = neighborIndex + 1;
        break;
      }
    }
    result.insert(insertAt, id);
  }
  return result;
}
