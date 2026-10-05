import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_command_palette.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
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
  final Map<KeyboardActionId, GlobalKey> _rowKeys =
      <KeyboardActionId, GlobalKey>{};
  final ScrollController _resultsScrollController = ScrollController();

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
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _updateQuery(String query) {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _matches.isEmpty) {
        return;
      }
      final rowContext =
          _rowKeys[_matches[_selectedIndex].definition.id]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: AleraTokens.durationFast,
        );
      } else if (_resultsScrollController.hasClients) {
        // The target row is not built yet; jump near it by the average row
        // height so the next frame builds it, then center it precisely.
        final position = _resultsScrollController.position;
        final rowExtent =
            (position.maxScrollExtent + position.viewportDimension) /
            _matches.length;
        _resultsScrollController.jumpTo(
          (_selectedIndex * rowExtent).clamp(0.0, position.maxScrollExtent),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _matches.isEmpty) {
            return;
          }
          final context =
              _rowKeys[_matches[_selectedIndex].definition.id]?.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(context, alignment: 0.5);
          }
        });
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
      return AleraEmptyState(
        icon: AleraIcons.searchOff,
        message: query.isEmpty
            ? 'No commands are available.'
            : 'No commands match "$query".',
      );
    }
    final isMacOS = resolver.platform.isMacOS;
    return ListView.builder(
      key: const ValueKey<String>('command-palette-results'),
      controller: _resultsScrollController,
      padding: EdgeInsets.zero,
      itemCount: _matches.length,
      itemBuilder: (context, index) {
        final definition = _matches[index].definition;
        final selected = index == _selectedIndex;
        final shortcuts = <String>[
          for (final chord in resolver.effectiveChords(definition.id))
            chord.format(isMacOS: isMacOS),
        ];
        return Padding(
          key: _rowKeys.putIfAbsent(definition.id, () => GlobalKey()),
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
          child: AleraActiveRail(
            active: selected,
            child: Material(
              color: selected
                  ? AleraActiveRail.selectedColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              clipBehavior: .antiAlias,
              child: InkWell(
                key: ValueKey<KeyboardActionId>(definition.id),
                onTap: () {
                  setState(() => _selectedIndex = index);
                  _executeSelected();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: AleraTokens.space8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Tooltip(
                        message: definition.group.label,
                        child: Icon(
                          _groupIcon(definition.group),
                          size: AleraTokens.iconLg,
                          color: AleraTokens.foregroundMuted,
                        ),
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
                      if (shortcuts.isNotEmpty) ...<Widget>[
                        const SizedBox(width: AleraTokens.space12),
                        Wrap(
                          spacing: AleraTokens.space4,
                          children: <Widget>[
                            for (final shortcut in shortcuts)
                              AleraKeybindingBadge(label: shortcut),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _groupIcon(KeyboardActionGroup group) => switch (group) {
    .global => AleraIcons.command,
    .workspace => AleraIcons.folderSpecial,
    .tabs => AleraIcons.tabUnselected,
    .panes => AleraIcons.gridView,
  };
}
