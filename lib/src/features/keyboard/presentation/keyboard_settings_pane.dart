import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings pane for viewing and remapping keyboard shortcuts.
class KeyboardSettingsPane extends ConsumerStatefulWidget {
  const KeyboardSettingsPane({super.key});

  @override
  ConsumerState<KeyboardSettingsPane> createState() =>
      _KeyboardSettingsPaneState();
}

class _KeyboardSettingsPaneState extends ConsumerState<KeyboardSettingsPane> {
  final FocusNode _recordFocus = FocusNode(debugLabel: 'ShortcutRecorder');
  KeyboardActionId? _recordingId;
  final Map<KeyboardActionId, String> _errors = <KeyboardActionId, String>{};

  bool get _isMacOS => KeyboardPlatform.current.isMacOS;

  @override
  void dispose() {
    _recordFocus.dispose();
    super.dispose();
  }

  void _startRecording(KeyboardActionId id) {
    setState(() {
      _recordingId = id;
      _errors.remove(id);
    });
    _recordFocus.requestFocus();
  }

  void _cancelRecording() {
    if (_recordingId == null) {
      return;
    }
    setState(() => _recordingId = null);
  }

  KeyEventResult _handleRecordKey(FocusNode node, KeyEvent event) {
    final id = _recordingId;
    if (id == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelRecording();
      return KeyEventResult.handled;
    }
    // Swallow standalone modifier presses while the user is still composing.
    if (_isModifierKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    final modifiers = KeyModifierState.fromKeyboard(HardwareKeyboard.instance);
    final result = KeyChord.fromKeyEvent(event, modifiers, isMacOS: _isMacOS);
    if (result is KeyChordParseFailure) {
      setState(() => _errors[id] = result.message);
      return KeyEventResult.handled;
    }
    _applyCapturedChord(id, (result as KeyChordParseSuccess).chord);
    return KeyEventResult.handled;
  }

  Future<void> _applyCapturedChord(KeyboardActionId id, KeyChord chord) async {
    setState(() {
      _recordingId = null;
      _errors.remove(id);
    });
    final controller = ref.read(settingsControllerProvider.notifier);
    final resolver = KeybindingResolver(
      settings: ref.read(settingsControllerProvider).keyboard,
    );
    final conflict = resolver.findConflict(chord, excluding: id);
    final canonical = chord.toCanonicalString();
    if (conflict == null) {
      await controller.setActionBindings(id, <String>[canonical]);
      return;
    }
    final reassign = await _confirmReassign(chord, conflict, id);
    if (!reassign) {
      return;
    }
    // Drop the chord from the previous owner and assign it here, atomically.
    final reduced = resolver
        .effectiveChords(conflict)
        .where((existing) => existing != chord)
        .map((existing) => existing.toCanonicalString())
        .toList(growable: false);
    await controller.applyBindingChanges(<KeyboardActionId, List<String>?>{
      conflict: reduced,
      id: <String>[canonical],
    });
  }

  Future<bool> _confirmReassign(
    KeyChord chord,
    KeyboardActionId conflict,
    KeyboardActionId target,
  ) async {
    final conflictLabel = keybindingDefinitionsById[conflict]?.label ?? '';
    final targetLabel = keybindingDefinitionsById[target]?.label ?? '';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Shortcut Already in Use',
        message:
            '${chord.format(isMacOS: _isMacOS)} is assigned to '
            '"$conflictLabel". Reassign it to "$targetLabel"?',
        confirmLabel: 'Reassign',
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: settings);
    return Focus(
      focusNode: _recordFocus,
      onKeyEvent: _handleRecordKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _behaviorGroup(settings),
          for (final group in KeyboardActionGroup.values) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            _actionGroup(group, settings, resolver),
          ],
        ],
      ),
    );
  }

  Widget _behaviorGroup(KeyboardShortcutSettings settings) {
    return _GroupCard(
      title: 'Behavior',
      description: 'How shortcuts behave while a terminal is focused.',
      children: <Widget>[
        AleraSettingRow(
          title: 'When a Terminal Is Focused',
          description:
              'App first lets Alera capture combinations the shell would '
              'otherwise receive. Terminal first defers to the shell.',
          controlWidth: 220,
          child: AleraSegmentedButton<TerminalShortcutPolicy>(
            selected: settings.terminalPolicy,
            onSelectionChanged: (policy) => ref
                .read(settingsControllerProvider.notifier)
                .setTerminalShortcutPolicy(policy),
            segments: const <ButtonSegment<TerminalShortcutPolicy>>[
              ButtonSegment<TerminalShortcutPolicy>(
                value: TerminalShortcutPolicy.appFirst,
                label: Text('App First'),
              ),
              ButtonSegment<TerminalShortcutPolicy>(
                value: TerminalShortcutPolicy.terminalFirst,
                label: Text('Terminal First'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionGroup(
    KeyboardActionGroup group,
    KeyboardShortcutSettings settings,
    KeybindingResolver resolver,
  ) {
    final definitions = keybindingDefinitions
        .where((definition) => definition.group == group)
        .toList(growable: false);
    return _GroupCard(
      title: group.label,
      description: null,
      children: <Widget>[
        for (final definition in definitions)
          _ShortcutBindingRow(
            label: definition.label,
            description: definition.description,
            chords: resolver.effectiveChords(definition.id),
            disabled: settings.isDisabled(definition.id),
            modified: settings.hasOverride(definition.id),
            recording: _recordingId == definition.id,
            error: _errors[definition.id],
            isMacOS: _isMacOS,
            onRecordToggle: () {
              if (_recordingId == definition.id) {
                _cancelRecording();
              } else {
                _startRecording(definition.id);
              }
            },
            onReset: settings.hasOverride(definition.id)
                ? () => ref
                      .read(settingsControllerProvider.notifier)
                      .setActionBindings(definition.id, null)
                : null,
            onDisable: settings.isDisabled(definition.id)
                ? null
                : () => ref
                      .read(settingsControllerProvider.notifier)
                      .setActionBindings(definition.id, const <String>[]),
          ),
      ],
    );
  }
}

class _ShortcutBindingRow extends StatelessWidget {
  const _ShortcutBindingRow({
    required this.label,
    required this.description,
    required this.chords,
    required this.disabled,
    required this.modified,
    required this.recording,
    required this.error,
    required this.isMacOS,
    required this.onRecordToggle,
    required this.onReset,
    required this.onDisable,
  });

  final String label;
  final String description;
  final List<KeyChord> chords;
  final bool disabled;
  final bool modified;
  final bool recording;
  final String? error;
  final bool isMacOS;
  final VoidCallback onRecordToggle;
  final VoidCallback? onReset;
  final VoidCallback? onDisable;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: label,
      description: description,
      controlWidth: 280,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Expanded(child: _bindingDisplay(context)),
          const SizedBox(width: AleraTokens.space8),
          AleraIconButton(
            tooltip: recording ? 'Stop Recording' : 'Change Shortcut',
            icon: recording ? AleraIcons.close : AleraIcons.keyboard,
            onPressed: onRecordToggle,
          ),
          if (onReset != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Reset to Default',
              icon: AleraIcons.restore,
              onPressed: onReset!,
            ),
          ],
          if (onDisable != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Disable Shortcut',
              icon: AleraIcons.blocked,
              onPressed: onDisable!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bindingDisplay(BuildContext context) {
    final theme = Theme.of(context);
    if (recording) {
      return Text(
        'Press Keys… (Esc to Cancel)',
        textAlign: TextAlign.right,
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.accent),
      );
    }
    if (error case final String message) {
      return Text(
        message,
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
      );
    }
    if (disabled) {
      return Text(
        'Disabled',
        textAlign: TextAlign.right,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      );
    }
    if (chords.isEmpty) {
      return Text(
        'Unassigned',
        textAlign: TextAlign.right,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AleraTokens.space4,
      runSpacing: AleraTokens.space4,
      children: <Widget>[
        for (final chord in chords)
          AleraChip(label: chord.format(isMacOS: isMacOS)),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description case final String text) ...<Widget>[
                const SizedBox(height: AleraTokens.space4),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        AleraPanel(children: children),
      ],
    );
  }
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}
