import 'package:alera/src/design_system/forms/alera_compact_input.dart';
import 'package:flutter/material.dart';

final RegExp _timeOfDayPattern = RegExp(
  r'^(\d{1,2})(?:[:.]?(\d{2}))?\s*(?:([ap])\.?\s*(?:m\.?)?)?$',
  caseSensitive: false,
);

/// Parses a typed time of day: "9", "9:30", "18:05", "930", "9:30 pm",
/// "12am". Returns null for anything else, including out-of-range hours or
/// minutes and a 24-hour value with an am/pm suffix.
({int hour, int minute})? parseAleraTimeOfDay(String input) {
  final match = _timeOfDayPattern.firstMatch(input.trim());
  if (match == null) {
    return null;
  }
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2) ?? '0');
  if (minute > 59) {
    return null;
  }
  final meridiem = match.group(3)?.toLowerCase();
  if (meridiem == null) {
    return hour > 23 ? null : (hour: hour, minute: minute);
  }
  if (hour < 1 || hour > 12) {
    return null;
  }
  hour %= 12;
  if (meridiem == 'p') {
    hour += 12;
  }
  return (hour: hour, minute: minute);
}

/// Formats a time of day the way [AleraTimeOfDayField] displays it: "09:30".
String formatAleraTimeOfDay(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Typed time-of-day entry. Accepts the forms [parseAleraTimeOfDay] reads and
/// commits on blur or Enter. Unparseable text shows an inline error and keeps
/// the last valid value, so [onChanged] only ever sees a real time.
class const AleraTimeOfDayField({
  super.key,
  required final int hour,
  required final int minute,
  required final void Function(int hour, int minute) onChanged,
  final String? labelText,
  final bool enabled = true,
}) extends StatefulWidget {
  static const String invalidMessage = 'Use a time like 9:30 or 6:05 pm.';

  @override
  State<AleraTimeOfDayField> createState() => _AleraTimeOfDayFieldState();
}

class _AleraTimeOfDayFieldState extends State<AleraTimeOfDayField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatAleraTimeOfDay(widget.hour, widget.minute),
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'AleraTimeOfDayField');
  bool _invalid = false;

  /// Enter commits and then unfocuses, which commits again before the parent
  /// has rebuilt; this keeps the second commit from reporting the same time.
  ({int hour, int minute})? _emitted;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(AleraTimeOfDayField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        widget.hour != oldWidget.hour || widget.minute != oldWidget.minute;
    if (changed) {
      _emitted = null;
    }
    if (changed && !_focusNode.hasFocus) {
      _controller.text = formatAleraTimeOfDay(widget.hour, widget.minute);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted && !_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final parsed = parseAleraTimeOfDay(_controller.text);
    if (parsed == null) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _invalid = false;
      _controller.text = formatAleraTimeOfDay(parsed.hour, parsed.minute);
    });
    final current = _emitted ?? (hour: widget.hour, minute: widget.minute);
    if (parsed != current) {
      _emitted = parsed;
      widget.onChanged(parsed.hour, parsed.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraCompactFieldFrame(
      labelText: widget.labelText,
      errorText: _invalid ? AleraTimeOfDayField.invalidMessage : null,
      child: AleraCompactInput(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        hasError: _invalid,
        hintText: '09:00',
        keyboardType: TextInputType.datetime,
        semanticsLabel: widget.labelText,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
