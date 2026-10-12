import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';

/// An [AleraPropertyChip] that opens its editor or choices in an
/// [AleraPopover]: a composer property or a catalog filter. Without
/// [builder] the chip is read-only; [onClear] resets it.
class AutomationPopoverChip extends StatefulWidget {
  const AutomationPopoverChip({
    super.key,
    required this.value,
    this.builder,
    this.icon,
    this.label,
    this.tooltip,
    this.hasError = false,
    this.fromContext = false,
    this.width,
    this.onClear,
  });

  final String value;
  final AleraPopoverContentBuilder? builder;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool hasError;
  final bool fromContext;
  final double? width;
  final VoidCallback? onClear;

  @override
  State<AutomationPopoverChip> createState() => _AutomationPopoverChipState();
}

class _AutomationPopoverChipState extends State<AutomationPopoverChip> {
  final AleraPopoverController _popover = AleraPopoverController();

  @override
  void initState() {
    super.initState();
    _popover.addListener(_changed);
  }

  @override
  void dispose() {
    _popover
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    final chip = AleraPropertyChip(
      icon: widget.icon,
      label: widget.label,
      value: widget.value,
      tooltip: widget.tooltip,
      hasError: widget.hasError,
      fromContext: widget.fromContext,
      active: _popover.isOpen,
      onClear: widget.onClear,
      showChevron: builder != null,
      onTap: builder == null ? null : _popover.toggle,
    );
    if (builder == null) return chip;
    return AleraPopover(
      controller: _popover,
      toggleOnAnchorTap: false,
      width: widget.width,
      builder: builder,
      child: chip,
    );
  }
}
