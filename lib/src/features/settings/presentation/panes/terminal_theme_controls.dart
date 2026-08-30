import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';

const double _kSidebarIconSize = 16;

class const HexColorSettingRow({
  super.key,
  required final String title,
  required final String description,
  required final String? value,
  required final String fallback,
  required final ValueChanged<String?> onChanged,
}) extends StatefulWidget {
  @override
  State<HexColorSettingRow> createState() => _HexColorSettingRowState();
}

class _HexColorSettingRowState extends State<HexColorSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(HexColorSettingRow oldWidget) {
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

class const CursorShapeRow({
  super.key,
  required final TerminalCursorShape value,
  required final ValueChanged<TerminalCursorShape> onChanged,
}) extends StatelessWidget {
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
            value: .block,
            tooltip: 'Block',
            icon: _CursorGlyph(shape: .block),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: .bar,
            tooltip: 'Bar',
            icon: _CursorGlyph(shape: .bar),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: .underline,
            tooltip: 'Underline',
            icon: _CursorGlyph(shape: .underline),
          ),
        ],
      ),
    );
  }
}

class const _CursorGlyph({required final TerminalCursorShape shape})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? AleraTokens.foreground;
    final size = iconTheme.size ?? _kSidebarIconSize;
    final Widget glyph;
    Alignment alignment = .center;
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

class const ToolbarCornerRow({
  super.key,
  required final TerminalToolbarCorner value,
  required final ValueChanged<TerminalToolbarCorner> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Toolbar Corner',
      description: 'Where the pulse, composer, and refresh buttons sit on the terminal tab.',
      child: AleraDropdownField<TerminalToolbarCorner>(
        key: ValueKey<String>('terminal-toolbar-corner-${value.name}'),
        value: value,
        entries: <AleraDropdownFieldEntry<TerminalToolbarCorner>>[
          for (final corner in TerminalToolbarCorner.values)
            AleraDropdownFieldEntry<TerminalToolbarCorner>(
              value: corner,
              label: corner.label,
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final normalized = normalizeTerminalHexColor(value) ?? '#000000';
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}
