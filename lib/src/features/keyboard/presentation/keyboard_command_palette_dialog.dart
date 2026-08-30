import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showKeyboardCommandPalette(
  BuildContext context, {
  required ValueChanged<KeyboardActionId> onExecute,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  await showDialog<void>(
    context: context,
    builder: (_) => KeyboardCommandPaletteDialog(onExecute: onExecute),
  );
  if (previousFocus?.canRequestFocus ?? false) {
    previousFocus!.requestFocus();
  }
}

class const KeyboardCommandPaletteDialog({
  super.key,
  required final ValueChanged<KeyboardActionId> onExecute,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<KeyboardCommandPaletteDialog> createState() =>
      _KeyboardCommandPaletteDialogState();
}

class _KeyboardCommandPaletteDialogState
    extends ConsumerState<KeyboardCommandPaletteDialog> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  List<KeyboardCommandMatch> _matches = const <KeyboardCommandMatch>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode();
    _matches = filterKeyboardCommandPalette('');
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  void _updateQuery(String query) {
    setState(() {
      _matches = filterKeyboardCommandPalette(query);
      _selectedIndex = 0;
    });
  }

  void _moveSelection(int delta) {
    if (_matches.isEmpty) {
      return;
    }
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _matches.length;
      if (_selectedIndex < 0) {
        _selectedIndex += _matches.length;
      }
    });
  }

  void _executeSelected() {
    if (_matches.isEmpty) {
      return;
    }
    final id = _matches[_selectedIndex].definition.id;
    Navigator.of(context).pop();
    widget.onExecute(id);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _executeSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(
      settingsControllerProvider.select((state) => state.keyboard),
    );
    final resolver = KeybindingResolver(settings: settings);
    return Focus(
      onKeyEvent: _handleKey,
      child: AleraDialog(
        maxWidth: AleraTokens.dialogWideWidth,
        maxHeight: AleraTokens.dialogMaxHeight,
        child: SizedBox(
          width: AleraTokens.dialogWideWidth,
          height: AleraTokens.dialogMaxHeight,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space20),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Text('Command Palette', style: theme.textTheme.titleMedium),
                const SizedBox(height: AleraTokens.space16),
                AleraTextField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  autofocus: true,
                  hintText: 'Search commands',
                  prefixIcon: AleraIcons.search,
                  onChanged: _updateQuery,
                  onSubmitted: (_) => _executeSelected(),
                ),
                const SizedBox(height: AleraTokens.space12),
                Expanded(child: _buildResults(theme, resolver)),
                const Divider(height: AleraTokens.space20),
                Text(
                  'Use Up and Down to navigate, Enter to run, or Escape to close.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, KeybindingResolver resolver) {
    if (_matches.isEmpty) {
      final query = _queryController.text.trim();
      return Center(
        child: Text(
          query.isEmpty
              ? 'No commands are available.'
              : 'No commands match "$query".',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
          textAlign: .center,
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey<String>('command-palette-results'),
      padding: EdgeInsets.zero,
      itemCount: _matches.length,
      itemBuilder: (context, index) {
        final definition = _matches[index].definition;
        final selected = index == _selectedIndex;
        final chords = resolver.effectiveChords(definition.id);
        final shortcut = chords.isEmpty
            ? 'No shortcut'
            : chords
                  .map(
                    (chord) => chord.format(isMacOS: resolver.platform.isMacOS),
                  )
                  .join('  ');
        return Material(
          color: selected ? AleraTokens.accentSubtle : null,
          child: InkWell(
            key: ValueKey<KeyboardActionId>(definition.id),
            onTap: () {
              setState(() => _selectedIndex = index);
              _executeSelected();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    AleraIcons.keyboard,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Text(
                          definition.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AleraTokens.space2),
                        Text(
                          definition.description,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Text(shortcut, style: AleraTokens.monoStyle),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
