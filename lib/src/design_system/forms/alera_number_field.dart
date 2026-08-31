import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

const double _kStepperIconSize = 14;
const double _kStepperWidth = 26;
const double _kStepperGroupHeight = 36;

/// Numeric input paired with a stacked increment/decrement stepper. Commits on
/// submit/blur, clamps to [min]/[max], and formats based on [step] precision
/// unless [decimalPlaces] is provided.
class const AleraNumberField({
  super.key,
  required final double value,
  required final double min,
  required final double max,
  required final double step,
  required final ValueChanged<double> onChanged,
  final TextEditingController? controller,
  final int? decimalPlaces,
  final String? suffix,
}) extends StatefulWidget {
  @override
  State<AleraNumberField> createState() => _AleraNumberFieldState();
}

class _AleraNumberFieldState extends State<AleraNumberField> {
  late TextEditingController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(AleraNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller =
          widget.controller ??
          TextEditingController(text: _format(widget.value));
      return;
    }
    if (widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    if (widget.decimalPlaces case final decimalPlaces?) {
      return value.toStringAsFixed(decimalPlaces);
    }
    if (widget.step < 0.1) {
      return value.toStringAsFixed(2);
    }
    return value.toStringAsFixed(1);
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _controller.text = _format(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max).toDouble();
    _controller.text = _format(clamped);
    if (clamped != widget.value) {
      widget.onChanged(clamped);
    }
  }

  void _step(double delta) {
    widget.onChanged(
      (widget.value + delta).clamp(widget.min, widget.max).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: .number,
            contextMenuBuilder: (context, editableTextState) {
              return AleraTextActionsScope.buildContextMenu(
                context,
                editableTextState,
                textActionsEnabled: false,
              );
            },
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
            decoration: InputDecoration(suffixText: widget.suffix),
          ),
        ),
        const SizedBox(width: AleraTokens.space8),
        SizedBox(
          width: _kStepperWidth,
          height: _kStepperGroupHeight,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              Expanded(
                child: _StepperButton(
                  icon: AleraIcons.chevronUp,
                  position: .top,
                  onPressed: () => _step(widget.step),
                ),
              ),
              Expanded(
                child: _StepperButton(
                  icon: AleraIcons.chevronDown,
                  position: .bottom,
                  onPressed: () => _step(-widget.step),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _StepperPosition { top, bottom }

class const _StepperButton({
  required final IconData icon,
  required final _StepperPosition position,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = position == _StepperPosition.top
        ? const BorderRadius.only(
            topLeft: .circular(AleraTokens.radiusSm),
            topRight: .circular(AleraTokens.radiusSm),
          )
        : const BorderRadius.only(
            bottomLeft: .circular(AleraTokens.radiusSm),
            bottomRight: .circular(AleraTokens.radiusSm),
          );
    final border = position == _StepperPosition.top
        ? const Border(
            top: BorderSide(color: AleraTokens.borderSubtle),
            left: BorderSide(color: AleraTokens.borderSubtle),
            right: BorderSide(color: AleraTokens.borderSubtle),
            bottom: BorderSide(color: AleraTokens.borderSubtle, width: 0.5),
          )
        : const Border(
            top: BorderSide(color: AleraTokens.borderSubtle, width: 0.5),
            left: BorderSide(color: AleraTokens.borderSubtle),
            right: BorderSide(color: AleraTokens.borderSubtle),
            bottom: BorderSide(color: AleraTokens.borderSubtle),
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(borderRadius: radius, border: border),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: _kStepperIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}
