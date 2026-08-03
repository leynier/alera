import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';

const double kPickerMenuMaxHeight = 220;

List<String> filterOrdered(Iterable<String> values, String query) {
  final normalized = query.trim().toLowerCase();
  final matches = normalized.isEmpty
      ? values.toList(growable: false)
      : <String>[
          ...values.where(
            (value) => value.toLowerCase().startsWith(normalized),
          ),
          ...values.where((value) {
            final lower = value.toLowerCase();
            return !lower.startsWith(normalized) && lower.contains(normalized);
          }),
        ];
  return matches;
}

class SettingsTextRow extends StatefulWidget {
  const SettingsTextRow({
    super.key,
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
  State<SettingsTextRow> createState() => _SettingsTextRowState();
}

class _SettingsTextRowState extends State<SettingsTextRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(SettingsTextRow oldWidget) {
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

class SettingsAutocompleteMenu extends StatelessWidget {
  const SettingsAutocompleteMenu({
    super.key,
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
        constraints: const BoxConstraints(maxHeight: kPickerMenuMaxHeight),
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

class SettingsNumberRow extends StatelessWidget {
  const SettingsNumberRow({
    super.key,
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

class SettingsIntegerRow extends StatelessWidget {
  const SettingsIntegerRow({
    super.key,
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

/// A settings row whose control is an action button. The button shows a spinner
/// and disables itself while [onPressed] is running, so callers only supply the
/// async action and the row owns the in-flight state.
class SettingsButtonRow extends StatefulWidget {
  const SettingsButtonRow({
    super.key,
    required this.title,
    required this.description,
    required this.buttonLabel,
    this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final Future<void> Function()? onPressed;

  @override
  State<SettingsButtonRow> createState() => _SettingsButtonRowState();
}

class _SettingsButtonRowState extends State<SettingsButtonRow> {
  bool _busy = false;

  Future<void> _handlePressed() async {
    final action = widget.onPressed;
    if (action == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: enabled ? _handlePressed : null,
          child: _busy
              ? const SizedBox(
                  height: AleraTokens.space16,
                  width: AleraTokens.space16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.buttonLabel),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.secondary,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Optional control rendered before the switch (e.g., a pin toggle).
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ?secondary,
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
