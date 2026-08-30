import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class const SettingsFontAutocompleteRow({
  super.key,
  required final String title,
  required final String description,
  required final String value,
  required final List<String> suggestions,
  required final ValueChanged<String> onChanged,
}) extends StatefulWidget {
  @override
  State<SettingsFontAutocompleteRow> createState() =>
      _SettingsFontAutocompleteRowState();
}

class _SettingsFontAutocompleteRowState
    extends State<SettingsFontAutocompleteRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _open = false;
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode(debugLabel: 'TerminalFontFamily');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(SettingsFontAutocompleteRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
    if (widget.suggestions != oldWidget.suggestions) {
      _syncHighlightedIndex();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> get _filteredSuggestions {
    return filterOrdered(widget.suggestions, _controller.text);
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      return;
    }
    Future<void>.delayed(AleraTokens.durationFast, () {
      if (!mounted || _focusNode.hasFocus) {
        return;
      }
      _commitValue(_controller.text);
    });
  }

  void _openMenu() {
    setState(() {
      _open = true;
      _syncHighlightedIndex();
    });
  }

  void _syncHighlightedIndex() {
    final suggestions = _filteredSuggestions;
    if (!_open || suggestions.isEmpty) {
      _highlightedIndex = -1;
      return;
    }
    final selectedIndex = suggestions.indexOf(widget.value);
    _highlightedIndex = selectedIndex >= 0 ? selectedIndex : 0;
  }

  void _commitValue(String value) {
    final next = value.trim();
    if (next.isEmpty) {
      _controller.text = widget.value;
      setState(() => _open = false);
      return;
    }
    _controller.text = next;
    if (next != widget.value) {
      widget.onChanged(next);
    }
    setState(() => _open = false);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _filteredSuggestions;
    if (event.logicalKey == LogicalKeyboardKey.escape && _open) {
      setState(() => _open = false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _open = true;
        if (suggestions.isNotEmpty) {
          _highlightedIndex = _highlightedIndex < 0
              ? 0
              : (_highlightedIndex + 1).clamp(0, suggestions.length - 1);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _open = true;
        if (suggestions.isNotEmpty) {
          _highlightedIndex = _highlightedIndex < 0
              ? suggestions.length - 1
              : (_highlightedIndex - 1).clamp(0, suggestions.length - 1);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_open &&
          _highlightedIndex >= 0 &&
          _highlightedIndex < suggestions.length) {
        _commitValue(suggestions[_highlightedIndex]);
      } else {
        _commitValue(_controller.text);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _filteredSuggestions;
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: Focus(
        onKeyEvent: _handleKey,
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            AleraTextField(
              key: const ValueKey<String>('terminal-font-family-field'),
              controller: _controller,
              focusNode: _focusNode,
              onTap: _openMenu,
              onChanged: (value) {
                setState(() {
                  _open = true;
                  _syncHighlightedIndex();
                });
              },
              onSubmitted: _commitValue,
              onEditingComplete: () => _commitValue(_controller.text),
              hintText: 'SF Mono',
              suffix: Row(
                mainAxisSize: .min,
                children: <Widget>[
                  if (_controller.text.isNotEmpty)
                    AleraIconButton(
                      tooltip: 'Clear',
                      icon: AleraIcons.cancel,
                      iconSize: 16,
                      minSize: 28,
                      onPressed: () {
                        _controller.clear();
                        _openMenu();
                        _focusNode.requestFocus();
                      },
                    ),
                  AleraIconButton(
                    tooltip: 'Fonts',
                    icon: _open ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                    iconSize: 18,
                    minSize: 28,
                    onPressed: () {
                      setState(() {
                        _open = !_open;
                        _syncHighlightedIndex();
                      });
                      _focusNode.requestFocus();
                    },
                  ),
                ],
              ),
            ),
            if (_open) ...<Widget>[
              const SizedBox(height: AleraTokens.space6),
              SettingsAutocompleteMenu(
                emptyText: 'No matching fonts.',
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final font = suggestions[index];
                  final active = index == _highlightedIndex;
                  final selected = font == widget.value;
                  return AleraMenuItem(
                    label: font,
                    active: active,
                    selected: selected,
                    onHover: () => setState(() => _highlightedIndex = index),
                    onTap: () => _commitValue(font),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
