import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';

part 'keyboard_shortcut_settings.mapper.dart';

/// User customization of keyboard shortcuts.
///
/// [overrides] maps an action to the canonical chord strings the user assigned.
/// Three states are encoded:
/// - absent key: use the registry default for the action,
/// - present with a non-empty list: use those chords,
/// - present with an empty list: the action is explicitly disabled.
@MappableClass()
class const KeyboardShortcutSettings({
  this.overrides = const <KeyboardActionId, List<String>>{},
  this.terminalPolicy = TerminalShortcutPolicy.appFirst,
}) with KeyboardShortcutSettingsMappable {
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
      next[id] = List<String>.unmodifiableOf(chords);
    }
    return KeyboardShortcutSettings(
      overrides: Map<KeyboardActionId, List<String>>.unmodifiableOf(next),
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

  factory fromJson(Map<String, Object?> json) =>
      KeyboardShortcutSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
