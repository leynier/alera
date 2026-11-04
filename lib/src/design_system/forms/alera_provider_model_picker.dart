import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';

/// One chip that names the current agent and model and opens a searchable
/// [AleraSectionedPicker] with a section per agent and a row per model.
///
/// The caller builds the sections, so the same picker serves any list of
/// providers. Picking a row calls [onSelected] and closes the popover; the
/// optional footer action (such as Open Provider Settings) closes it first.
/// A disabled or [loading] chip keeps its label and width so the controls
/// around it do not move while the catalog is unavailable. With
/// [shrinkLabel] the label ellipsizes to fit a chip given less room than it
/// needs, so the chip must then have a bounded width, as inside a
/// [Flexible].
class const AleraProviderModelPicker<T>({
  super.key,
  required final String label,
  required final List<AleraPickerSection<T>> sections,
  required final ValueChanged<T> onSelected,
  final Widget? leading,
  final T? selectedValue,
  final AleraPopoverController? controller,
  final bool enabled = true,
  final bool loading = false,
  final String? tooltip,
  final String searchHintText = 'Search agents and models',
  final String emptyMessage = 'No agents or models match.',
  final String? footerActionLabel,
  final IconData footerActionIcon = AleraIcons.settings,
  final VoidCallback? onFooterAction,
  final bool shrinkLabel = false,
}) extends StatefulWidget {
  @override
  State<AleraProviderModelPicker<T>> createState() =>
      _AleraProviderModelPickerState<T>();
}

class _AleraProviderModelPickerState<T>
    extends State<AleraProviderModelPicker<T>> {
  AleraPopoverController? _ownedController;

  AleraPopoverController get _controller =>
      widget.controller ?? (_ownedController ??= AleraPopoverController());

  bool get _interactive => widget.enabled && !widget.loading;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_keepClosedWhileDisabled);
  }

  @override
  void dispose() {
    _controller.removeListener(_keepClosedWhileDisabled);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AleraProviderModelPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.controller ?? _ownedController;
    if (previous != _controller) {
      previous?.removeListener(_keepClosedWhileDisabled);
      _controller.addListener(_keepClosedWhileDisabled);
    }
    _keepClosedWhileDisabled();
  }

  /// A disabled picker never offers rows, even when its controller is opened
  /// from outside (a keyboard shortcut) or it turned disabled while open.
  void _keepClosedWhileDisabled() {
    if (!_interactive && _controller.isOpen) _controller.close();
  }

  void _select(T value, VoidCallback close) {
    close();
    widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final chip = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _AleraProviderModelChip(
        label: widget.label,
        leading: widget.leading,
        loading: widget.loading,
        active: _controller.isOpen,
        shrinkLabel: widget.shrinkLabel,
        onTap: _interactive ? _controller.toggle : null,
      ),
    );
    return AleraPopover(
      controller: _controller,
      toggleOnAnchorTap: false,
      width: AleraTokens.dialogCompactWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      builder: (context, close) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Flexible(
            child: AleraSectionedPicker<T>(
              sections: widget.sections,
              selectedValue: widget.selectedValue,
              searchHintText: widget.searchHintText,
              emptyMessage: widget.emptyMessage,
              maxListHeight: AleraTokens.agentChatRequestMaxHeight,
              onSelected: (value) => _select(value, close),
            ),
          ),
          if (widget.onFooterAction case final VoidCallback action
              when widget.footerActionLabel != null) ...<Widget>[
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('provider-model-picker-footer'),
                  onPressed: () {
                    close();
                    action();
                  },
                  icon: Icon(widget.footerActionIcon, size: AleraTokens.iconSm),
                  label: Text(widget.footerActionLabel!),
                ),
              ),
            ),
          ],
        ],
      ),
      child: widget.tooltip == null
          ? chip
          : Tooltip(message: widget.tooltip!, child: chip),
    );
  }
}

class const _AleraProviderModelChip({
  required final String label,
  required final Widget? leading,
  required final bool loading,
  required final bool active,
  required final bool shrinkLabel,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AleraTokens.contextMenuWidth),
      child: Text(
        label,
        maxLines: 1,
        overflow: .ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
    return HoverContainer(
      onTap: onTap,
      baseColor: active ? AleraTokens.surfaceElevated : Colors.transparent,
      borderRadius: AleraTokens.radiusSm,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (leading case final Widget leading) ...<Widget>[
            Opacity(
              opacity: enabled || loading ? 1 : AleraTokens.disabledOpacity,
              child: leading,
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
          if (shrinkLabel) Flexible(child: text) else text,
          const SizedBox(width: AleraTokens.space2),
          // The trailing slot keeps one size so the chip never resizes when
          // the catalog finishes loading.
          SizedBox.square(
            dimension: AleraTokens.iconSm,
            child: loading
                ? const CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                    color: AleraTokens.foregroundFaint,
                  )
                : Icon(
                    AleraIcons.chevronDown,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundFaint,
                  ),
          ),
        ],
      ),
    );
  }
}
