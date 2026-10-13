import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unit offered by [AleraDurationField], from smallest to largest.
enum AleraDurationUnit {
  seconds(1, 'Seconds', 'second'),
  minutes(60, 'Minutes', 'minute'),
  hours(3600, 'Hours', 'hour'),
  days(86400, 'Days', 'day');

  AleraDurationUnit(this.inSeconds, this.label, this.singular);

  /// Length of one unit in seconds.
  final int inSeconds;

  /// Title Case label for the unit dropdown.
  final String label;

  /// Lowercase singular noun used in prose such as "1 day".
  final String singular;
}

/// The largest of [units] that divides [seconds] evenly, or the smallest of
/// [units] when none does (or when [seconds] is zero).
AleraDurationUnit aleraDurationDisplayUnit(
  int seconds, [
  List<AleraDurationUnit> units = AleraDurationUnit.values,
]) {
  final ordered = List<AleraDurationUnit>.of(units)
    ..sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
  if (seconds != 0) {
    for (final unit in ordered.reversed) {
      if (seconds % unit.inSeconds == 0) return unit;
    }
  }
  return ordered.first;
}

/// Human label for a duration in whole seconds: "90 seconds", "15 minutes",
/// "2 hours", "1 day". Uses the largest unit that divides the value.
String aleraDurationLabel(int seconds) {
  final unit = aleraDurationDisplayUnit(seconds);
  final count = seconds ~/ unit.inSeconds;
  final noun = count.abs() == 1 ? unit.singular : '${unit.singular}s';
  return '$count $noun';
}

/// Duration input as a number plus a unit dropdown, reporting whole seconds
/// through [onChanged] on every valid edit.
///
/// The value is shown in the largest of [units] that divides it. Values are
/// never clamped: range checks belong to the caller, which passes the message
/// back as [errorText].
///
/// Phone copy of the desktop `AleraDurationField`.
class const AleraDurationField({
  super.key,
  required final int seconds,
  required final ValueChanged<int> onChanged,
  final List<AleraDurationUnit> units = AleraDurationUnit.values,
  final String? labelText,
  final String? errorText,
  final bool enabled = true,
}) extends StatefulWidget {
  static const String invalidMessage = 'Enter a number.';

  @override
  State<AleraDurationField> createState() => _AleraDurationFieldState();
}

class _AleraDurationFieldState extends State<AleraDurationField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'AleraDurationField');
  late AleraDurationUnit _unit;

  /// The last value this field reported, so the parent echoing it back does
  /// not reformat what the user is typing or switch the unit under them.
  int? _lastEmitted;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _showValue(widget.seconds);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(AleraDurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedOutside =
        widget.seconds != oldWidget.seconds && widget.seconds != _lastEmitted;
    if (changedOutside || !widget.units.contains(_unit)) {
      _showValue(widget.seconds);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showValue(int seconds) {
    _unit = aleraDurationDisplayUnit(seconds, widget.units);
    _controller.text = _format(seconds / _unit.inSeconds);
    _lastEmitted = null;
    _invalid = false;
  }

  String _format(num amount) {
    if (amount == amount.roundToDouble()) return amount.round().toString();
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double? _parse(String text) {
    final parsed = double.tryParse(text.trim());
    return parsed == null || !parsed.isFinite ? null : parsed;
  }

  void _emit(double amount) {
    final seconds = (amount * _unit.inSeconds).round();
    _lastEmitted = seconds;
    if (seconds != widget.seconds) widget.onChanged(seconds);
  }

  void _handleTextChanged(String text) {
    final amount = _parse(text);
    setState(() => _invalid = amount == null);
    if (amount != null) _emit(amount);
  }

  void _handleUnitChanged(AleraDurationUnit unit) {
    setState(() => _unit = unit);
    final amount = _parse(_controller.text);
    if (amount != null) _emit(amount);
  }

  void _handleFocusChanged() {
    if (mounted && !_focusNode.hasFocus && _invalid) {
      setState(() => _showValue(widget.seconds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callerError = widget.errorText;
    final error = _invalid
        ? AleraDurationField.invalidMessage
        : (callerError != null && callerError.isNotEmpty ? callerError : null);
    final label = widget.labelText;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
        ],
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Semantics(
                label: label,
                child: AleraTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  dense: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: _handleTextChanged,
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              flex: 3,
              child: AleraDropdownField<AleraDurationUnit>(
                value: _unit,
                enabled: widget.enabled,
                entries: <AleraDropdownFieldEntry<AleraDurationUnit>>[
                  for (final unit in widget.units)
                    AleraDropdownFieldEntry<AleraDurationUnit>(
                      value: unit,
                      label: unit.label,
                    ),
                ],
                onChanged: _handleUnitChanged,
              ),
            ),
          ],
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
      ],
    );
  }
}
