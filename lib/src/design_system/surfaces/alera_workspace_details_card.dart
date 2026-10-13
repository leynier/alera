import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class const AleraWorkspaceDetailRow({
  required this.label,
  required this.leading,
  this.subtitle,
  this.subtitleColor,
  this.trailing,
  this.onPressed,
  this.onMenu,
  this.pressOpensMenu = false,
  this.hasMenu = false,
  this.hint,
}) {
  final String label;
  final Widget leading;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onPressed;

  /// Opens the row's menu below [anchor], the row's global bounds.
  final ValueChanged<Rect>? onMenu;

  /// Routes the primary segment to [onMenu] instead of [onPressed].
  final bool pressOpensMenu;

  /// Keeps a disabled menu segment in place while [onMenu] is temporarily
  /// unavailable, so a busy row does not change width.
  final bool hasMenu;
  final String? hint;
  bool get showsMenu => hasMenu || onMenu != null;
}

class const AleraWorkspaceDetailsCard({
  super.key,
  required this.rows,
  this.afterBranch,
  this.density = WorkspaceDetailsDensity.full,
  this.onOptions,
}) extends StatelessWidget {
  final List<AleraWorkspaceDetailRow> rows;
  final Widget? afterBranch;
  final WorkspaceDetailsDensity density;
  final ValueChanged<Rect>? onOptions;

  @override
  Widget build(BuildContext context) {
    final essential = density == WorkspaceDetailsDensity.essential;
    final compact = density != WorkspaceDetailsDensity.full;
    // Essential density folds Host and Open In into one options row that
    // keeps the host visible, so the card never spends a row on a lone icon.
    final workspace = <Widget>[
      if (!essential)
        for (var i = 0; i < rows.length && i < 2; i++)
          _DetailRow(row: rows[i], compact: compact)
      else if (onOptions != null && rows.isNotEmpty)
        _DetailRow(
          compact: true,
          row: AleraWorkspaceDetailRow(
            label: rows.first.label,
            leading: rows.first.leading,
            hint: 'Workspace Options',
            onMenu: onOptions,
            pressOpensMenu: true,
          ),
        ),
    ];
    final git = <Widget>[
      for (var i = 2; i < rows.length; i++) ...[
        _DetailRow(row: rows[i], compact: compact),
        if (i == 2 && afterBranch != null) afterBranch!,
      ],
    ];
    Widget section(List<Widget> children) => Padding(
      padding: const EdgeInsets.all(AleraTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return Material(
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        side: const BorderSide(color: AleraTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workspace.isNotEmpty) section(workspace),
          if (workspace.isNotEmpty && git.isNotEmpty)
            const Divider(
              height: AleraTokens.dividerExtent,
              thickness: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
          if (git.isNotEmpty) section(git),
        ],
      ),
    );
  }
}

/// Fixed slot for a row's leading glyph, so host OS marks, codicons and Lucide
/// icons share one text column regardless of their optical width.
class const AleraWorkspaceDetailLeading({
  super.key,
  required this.child,
  this.enabled = true,
}) extends StatelessWidget {
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: AleraTokens.iconLg,
    height: AleraTokens.iconLg,
    child: Center(
      child: IconTheme.merge(
        data: IconThemeData(
          size: AleraTokens.iconMd,
          color: enabled
              ? AleraTokens.foregroundMuted
              : AleraTokens.foregroundFaint,
        ),
        child: child,
      ),
    ),
  );
}

/// Small indeterminate indicator sized for a detail row's icon slot.
class const AleraWorkspaceDetailSpinner({
  super.key,
  this.size = AleraTokens.iconMd,
  this.color = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: AleraTokens.strokeThin,
      color: color,
    ),
  );
}

/// A detail row: one primary action and an optional menu segment, divided by a
/// hairline. The whole row tints on hover and the hovered segment tints again,
/// so both halves read as one control with two targets.
class const AleraWorkspaceDetailControl({
  super.key,
  required this.child,
  required this.tooltip,
  this.onPressed,
  this.onMenu,
  this.pressOpensMenu = false,
  this.menuTooltip,
}) extends StatefulWidget {
  final Widget child;
  final String tooltip;
  final VoidCallback? onPressed;
  final ValueChanged<Rect>? onMenu;
  final bool pressOpensMenu;
  final String? menuTooltip;
  @override
  State<AleraWorkspaceDetailControl> createState() =>
      _AleraWorkspaceDetailControlState();
}

class _AleraWorkspaceDetailControlState
    extends State<AleraWorkspaceDetailControl> {
  bool _hovered = false;

  void _openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMenu?.call(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(AleraTokens.radiusMd);
    final split = widget.menuTooltip != null;
    final onPressed = widget.pressOpensMenu
        ? (widget.onMenu == null ? null : _openMenu)
        : widget.onPressed;
    final interactive = onPressed != null || widget.onMenu != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AleraTokens.durationFast,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: AleraTokens.space32),
        decoration: BoxDecoration(
          color: _hovered && interactive
              ? AleraTokens.surfaceVariant
              : Colors.transparent,
          borderRadius: const BorderRadius.all(radius),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AleraWorkspaceDetailSegment(
                  tooltip: widget.tooltip,
                  onPressed: onPressed,
                  borderRadius: split
                      ? const BorderRadius.horizontal(left: radius)
                      : const BorderRadius.all(radius),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: AleraTokens.space6,
                  ),
                  child: widget.child,
                ),
              ),
              if (split) ...[
                const Center(
                  child: SizedBox(
                    width: AleraTokens.dividerExtent,
                    height: AleraTokens.space16,
                    child: ColoredBox(color: AleraTokens.border),
                  ),
                ),
                AleraWorkspaceDetailSegment(
                  tooltip: widget.menuTooltip,
                  onPressed: widget.onMenu == null ? null : _openMenu,
                  borderRadius: const BorderRadius.horizontal(right: radius),
                  child: SizedBox(
                    width: AleraTokens.space32,
                    child: Icon(
                      AleraIcons.chevronDown,
                      size: AleraTokens.iconMd,
                      color: widget.onMenu == null
                          ? AleraTokens.foregroundFaint
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keyboard-reachable tappable surface used inside workspace details rows:
/// Tab focuses it, Enter or Space activates it, and a focus ring shows while
/// navigating by keyboard. A null [onPressed] renders it disabled.
class const AleraWorkspaceDetailSegment({
  super.key,
  required this.child,
  this.onPressed,
  this.tooltip,
  this.padding = EdgeInsets.zero,
  this.borderRadius = const BorderRadius.all(
    Radius.circular(AleraTokens.radiusMd),
  ),
  this.baseColor = Colors.transparent,
  this.hoverColor = AleraTokens.surfaceElevated,
}) extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color baseColor;
  final Color hoverColor;
  @override
  State<AleraWorkspaceDetailSegment> createState() =>
      _AleraWorkspaceDetailSegmentState();
}

class _AleraWorkspaceDetailSegmentState
    extends State<AleraWorkspaceDetailSegment> {
  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };
  bool _hovered = false;
  bool _focused = false;
  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onPressed?.call();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget segment = FocusableActionDetector(
      enabled: enabled,
      shortcuts: _shortcuts,
      actions: _actions,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: enabled && (_hovered || _focused)
                ? widget.hoverColor
                : widget.baseColor,
            borderRadius: widget.borderRadius,
          ),
          foregroundDecoration: enabled && _focused
              ? BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(
                    color: AleraTokens.focusRing,
                    width: AleraTokens.dividerExtent,
                  ),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
    segment = Semantics(button: true, enabled: enabled, child: segment);
    return widget.tooltip == null
        ? segment
        : Tooltip(message: widget.tooltip, child: segment);
  }
}

class const _DetailRow({required this.row, this.compact = false})
    extends StatelessWidget {
  final AleraWorkspaceDetailRow row;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = row.pressOpensMenu
        ? row.onMenu != null
        : row.onPressed != null;
    final subtitle = compact ? null : row.subtitle;
    return AleraWorkspaceDetailControl(
      tooltip: row.hint ?? row.label,
      onPressed: row.onPressed,
      onMenu: row.onMenu,
      pressOpensMenu: row.pressOpensMenu,
      menuTooltip: row.showsMenu ? '${row.label} Options' : null,
      child: Row(
        children: [
          AleraWorkspaceDetailLeading(enabled: enabled, child: row.leading),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: row.subtitleColor ?? AleraTokens.foregroundMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (row.trailing != null) ...[
            const SizedBox(width: AleraTokens.space8),
            row.trailing!,
          ],
        ],
      ),
    );
  }
}
