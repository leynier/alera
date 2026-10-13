import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_compact_input.dart';
import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Local date and time entry: a date button that opens the themed date picker
/// beside an [AleraTimeOfDayField]. With [clearable], a Clear button resets
/// the value to null. A time typed before any date is kept and applied once a
/// date is picked.
class const AleraDateTimeField({
  super.key,
  required final DateTime? value,
  required final ValueChanged<DateTime?> onChanged,
  final String? labelText,
  final DateTime? firstDate,
  final DateTime? lastDate,
  final bool clearable = false,
  final bool enabled = true,
}) extends StatefulWidget {
  static const int _defaultHour = 9;
  static const int _pickerYearSpan = 10;

  @override
  State<AleraDateTimeField> createState() => _AleraDateTimeFieldState();
}

class _AleraDateTimeFieldState extends State<AleraDateTimeField> {
  int _pendingHour = AleraDateTimeField._defaultHour;
  int _pendingMinute = 0;

  int get _hour => widget.value?.hour ?? _pendingHour;
  int get _minute => widget.value?.minute ?? _pendingMinute;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first =
        widget.firstDate ??
        DateTime(now.year - AleraDateTimeField._pickerYearSpan);
    final last =
        widget.lastDate ??
        DateTime(now.year + AleraDateTimeField._pickerYearSpan);
    var initial = widget.value ?? now;
    if (initial.isBefore(first)) {
      initial = first;
    } else if (initial.isAfter(last)) {
      initial = last;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AleraTokens.surface,
            headerBackgroundColor: AleraTokens.surfaceVariant,
            headerForegroundColor: AleraTokens.foreground,
            dividerColor: AleraTokens.borderSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: .circular(AleraTokens.radiusXl),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    widget.onChanged(
      DateTime(picked.year, picked.month, picked.day, _hour, _minute),
    );
  }

  void _handleTimeChanged(int hour, int minute) {
    final value = widget.value;
    if (value == null) {
      setState(() {
        _pendingHour = hour;
        _pendingMinute = minute;
      });
      return;
    }
    widget.onChanged(
      DateTime(value.year, value.month, value.day, hour, minute),
    );
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final label = MaterialLocalizations.of(context).formatMediumDate(date);
    return date.year == DateTime.now().year ? label : '$label, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.value;
    final foreground = !widget.enabled
        ? AleraTokens.foregroundFaint
        : value == null
        ? AleraTokens.foregroundMuted
        : AleraTokens.foreground;
    final dateButton = Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.labelText,
      child: InkWell(
        onTap: widget.enabled ? _pickDate : null,
        borderRadius: .circular(AleraTokens.radiusMd),
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          height: AleraTokens.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                AleraIcons.date,
                size: AleraTokens.iconMd,
                color: foreground,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  value == null ? 'Choose Date' : _dateLabel(context, value),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AleraCompactFieldFrame(
      labelText: widget.labelText,
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          Expanded(flex: 3, child: dateButton),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            flex: 2,
            child: AleraTimeOfDayField(
              hour: _hour,
              minute: _minute,
              enabled: widget.enabled,
              onChanged: _handleTimeChanged,
            ),
          ),
          if (widget.clearable && value != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Clear',
              icon: AleraIcons.close,
              minSize: AleraTokens.controlHeight,
              onPressed: widget.enabled ? () => widget.onChanged(null) : null,
            ),
          ],
        ],
      ),
    );
  }
}
