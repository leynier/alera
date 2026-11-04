import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:flutter/services.dart';

/// A matched action plus the definition that owns it.
class const ResolvedShortcut({
  required final KeyboardActionId id,
  required final bool allowInTerminal,
});

/// Pure matching over the registry and a [KeyboardShortcutSettings] snapshot.
///
/// Holds no listeners or mutable state; construct one per resolution with the
/// current settings and platform.
class KeybindingResolver({
  required final KeyboardShortcutSettings settings,
  KeyboardPlatform? platform,
}) {
  this : platform = platform ?? KeyboardPlatform.current;

  final KeyboardPlatform platform;

  /// The chords that are effective for [id]: the user override when present,
  /// otherwise the platform default. A disabled action returns an empty list.
  List<KeyChord> effectiveChords(KeyboardActionId id) {
    final definition = keybindingDefinitionsById[id];
    if (definition == null) {
      return const <KeyChord>[];
    }
    final raw = settings.hasOverride(id)
        ? settings.overrides[id]!
        : definition.defaultBindings.forPlatform(platform);
    return _parseAll(raw);
  }

  /// Resolves a key event to the first matching action, or null. Bindings
  /// scoped to [focusScope], the surface holding the focus, win over global
  /// ones; bindings scoped to any other surface never match.
  ResolvedShortcut? resolveAction(
    KeyEvent event,
    KeyModifierState modifiers, {
    KeyboardActionScope focusScope = KeyboardActionScope.global,
  }) {
    if (event is! KeyDownEvent) {
      return null;
    }
    final candidates = <KeybindingDefinition>[
      if (focusScope != KeyboardActionScope.global)
        ...keybindingDefinitions.where((d) => d.scope == focusScope),
      ...keybindingDefinitions.where(
        (d) => d.scope == KeyboardActionScope.global,
      ),
    ];
    for (final definition in candidates) {
      final chords = effectiveChords(definition.id);
      for (final chord in chords) {
        if (chord.matches(event, modifiers, isMacOS: platform.isMacOS)) {
          return ResolvedShortcut(
            id: definition.id,
            allowInTerminal: definition.allowInTerminal,
          );
        }
      }
    }
    return null;
  }

  /// The first action (other than [excluding]) in the same scope whose
  /// effective chords already include [chord], or null when [chord] is free.
  /// A scoped binding sharing a chord with a global one is not a conflict.
  KeyboardActionId? findConflict(
    KeyChord chord, {
    required KeyboardActionId excluding,
  }) {
    final scope = keybindingDefinitionsById[excluding]?.scope;
    for (final definition in keybindingDefinitions) {
      if (definition.id == excluding || definition.scope != scope) {
        continue;
      }
      if (effectiveChords(definition.id).contains(chord)) {
        return definition.id;
      }
    }
    return null;
  }

  List<KeyChord> _parseAll(List<String> raw) {
    final chords = <KeyChord>[];
    for (final value in raw) {
      final parsed = KeyChord.parse(value);
      if (parsed is KeyChordParseSuccess) {
        chords.add(parsed.chord);
      }
    }
    return chords;
  }
}
