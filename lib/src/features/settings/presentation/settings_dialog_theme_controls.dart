part of 'settings_dialog.dart';

class _HexColorSettingRow extends StatefulWidget {
  const _HexColorSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String? value;
  final String fallback;
  final ValueChanged<String?> onChanged;

  @override
  State<_HexColorSettingRow> createState() => _HexColorSettingRowState();
}

class _HexColorSettingRowState extends State<_HexColorSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_HexColorSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (next != oldWidget.value && next != _controller.text) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      _controller.text = '';
      return;
    }

    final normalized = normalizeTerminalHexColor(raw);
    if (normalized == null) {
      _controller.text = widget.value ?? '';
      return;
    }
    _controller.text = normalized;
    if (normalized != widget.value) {
      widget.onChanged(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: Row(
        children: <Widget>[
          AleraColorSwatch(
            color: _colorFromHex(widget.value ?? widget.fallback),
            pickerTitle: widget.title,
            onColorChanged: (selectedColor) {
              if (!mounted) return;
              final r = (selectedColor.r * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final g = (selectedColor.g * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final b = (selectedColor.b * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final hex = '#$r$g$b';
              _controller.text = hex;
              _commit();
            },
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: AleraTextField(
              controller: _controller,
              onSubmitted: (_) => _commit(),
              onEditingComplete: _commit,
              hintText: widget.fallback,
            ),
          ),
        ],
      ),
    );
  }
}

class _CursorShapeRow extends StatelessWidget {
  const _CursorShapeRow({required this.value, required this.onChanged});

  final TerminalCursorShape value;
  final ValueChanged<TerminalCursorShape> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Cursor Shape',
      description: 'Cursor style for new terminal sessions.',
      child: AleraSegmentedButton<TerminalCursorShape>(
        selected: value,
        onSelectionChanged: onChanged,
        segments: const <ButtonSegment<TerminalCursorShape>>[
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.block,
            tooltip: 'Block',
            icon: _CursorGlyph(shape: TerminalCursorShape.block),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.bar,
            tooltip: 'Bar',
            icon: _CursorGlyph(shape: TerminalCursorShape.bar),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.underline,
            tooltip: 'Underline',
            icon: _CursorGlyph(shape: TerminalCursorShape.underline),
          ),
        ],
      ),
    );
  }
}

class _CursorGlyph extends StatelessWidget {
  const _CursorGlyph({required this.shape});

  final TerminalCursorShape shape;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? AleraTokens.foreground;
    final size = iconTheme.size ?? _kSidebarIconSize;
    final Widget glyph;
    Alignment alignment = Alignment.center;
    switch (shape) {
      case TerminalCursorShape.block:
        glyph = Container(
          width: size * 0.45,
          height: size * 0.72,
          color: color,
        );
        break;
      case TerminalCursorShape.bar:
        glyph = Container(width: 2, height: size * 0.72, color: color);
        break;
      case TerminalCursorShape.underline:
        glyph = Container(width: size * 0.6, height: 2, color: color);
        alignment = Alignment.bottomCenter;
        break;
    }
    return SizedBox(
      width: size,
      height: size,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: shape == TerminalCursorShape.underline
              ? const EdgeInsets.only(bottom: 2)
              : EdgeInsets.zero,
          child: glyph,
        ),
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final normalized = normalizeTerminalHexColor(value) ?? '#000000';
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}

class _NoSettingsResults extends StatelessWidget {
  const _NoSettingsResults({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: AleraEmptyState(message: 'No settings found.'),
        ),
        Positioned(
          top: AleraTokens.space16,
          right: AleraTokens.space16,
          child: AleraIconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: AleraIcons.close,
            minSize: 28,
          ),
        ),
      ],
    );
  }
}
