part of 'settings_dialog.dart';

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
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
              const SizedBox(height: AleraTokens.space4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
        AleraPanel(children: children),
      ],
    );
  }
}

class _TextSettingRow extends StatefulWidget {
  const _TextSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.trimValue = true,
  });

  final String title;
  final String description;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final bool trimValue;

  @override
  State<_TextSettingRow> createState() => _TextSettingRowState();
}

class _TextSettingRowState extends State<_TextSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final value = widget.trimValue ? _controller.text.trim() : _controller.text;
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: AleraTextField(
        controller: _controller,
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        hintText: widget.hintText,
      ),
    );
  }
}

class _FontAutocompleteSettingRow extends StatefulWidget {
  const _FontAutocompleteSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.suggestions,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String value;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;

  @override
  State<_FontAutocompleteSettingRow> createState() =>
      _FontAutocompleteSettingRowState();
}

class _FontAutocompleteSettingRowState
    extends State<_FontAutocompleteSettingRow> {
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
  void didUpdateWidget(_FontAutocompleteSettingRow oldWidget) {
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
    return _filterOrdered(widget.suggestions, _controller.text);
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
          mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
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
              _AutocompleteMenu(
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

class _AutocompleteMenu extends StatelessWidget {
  const _AutocompleteMenu({
    required this.emptyText,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String emptyText;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _kPickerMenuMaxHeight),
        child: itemCount == 0
            ? AleraEmptyState(message: emptyText)
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  vertical: AleraTokens.space4,
                ),
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
      ),
    );
  }
}

class _NumberSettingRow extends StatelessWidget {
  const _NumberSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: AleraNumberField(
        value: value,
        min: min,
        max: max,
        step: step,
        suffix: suffix,
        onChanged: onChanged,
      ),
    );
  }
}

class _IntegerSettingRow extends StatelessWidget {
  const _IntegerSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.suffix,
    required this.onChanged,
  });

  final String title;
  final String description;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: AleraNumberField(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        step: step.toDouble(),
        suffix: suffix,
        onChanged: (value) => onChanged(value.round()),
      ),
    );
  }
}

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}
