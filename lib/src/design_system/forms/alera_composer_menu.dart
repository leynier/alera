import 'dart:async';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// One row of an [AleraComposerMenu]: a [label] with an optional dimmed
/// [detail] after it. A row with a [disabledReason] stays listed and shows
/// the reason in place of the detail, but cannot be picked.
final class const AleraComposerMenuItem({
  required final String id,
  required final String label,
  final String? detail,
  final Widget? leading,
  final String? disabledReason,
}) {
  bool get enabled => disabledReason == null;
}

/// What a key pressed in the text field means to an open [AleraComposerMenu].
enum AleraComposerMenuKey { previous, next, pick, dismiss }

/// A suggestion list that opens from a text field while the person types,
/// such as `@` file mentions or `/` commands. It behaves like a combobox:
/// focus stays in the field, which forwards its keys through [keyFor], so
/// typing keeps filtering the list. Up and Down move the active row (it
/// wraps), Enter or Tab picks it, Escape closes the menu, and hovering or
/// clicking a row does the same with the pointer.
///
/// The active row uses [AleraActiveRail]. Because the field keeps focus, a
/// screen reader is told about the active row through an announcement each
/// time it changes. [loading] and an empty [items] list show [emptyMessage]
/// or [loadingMessage] instead of rows.
class const AleraComposerMenu({
  super.key,
  required final List<AleraComposerMenuItem> items,
  required final int activeIndex,
  required final ValueChanged<int> onPick,
  required final String semanticsLabel,
  final ValueChanged<int>? onActiveChanged,
  final String? title,
  final bool loading = false,
  final String emptyMessage = 'No matches.',
  final String loadingMessage = 'Searching…',
  final double maxHeight = defaultMaxHeight,
}) extends StatefulWidget {
  /// Eight rows tall, so a long result list scrolls instead of covering the
  /// conversation.
  static const double defaultMaxHeight = AleraTokens.menuRowHeight * 8;

  /// The menu meaning of [event], or `null` when the field should handle it.
  /// Modified arrows and Shift+Tab stay with the field so selecting text and
  /// moving focus backwards still work.
  static AleraComposerMenuKey? keyFor(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return null;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      return event is KeyDownEvent ? AleraComposerMenuKey.dismiss : null;
    }
    if (keyboard.isShiftPressed) return null;
    if (key == LogicalKeyboardKey.arrowUp) return AleraComposerMenuKey.previous;
    if (key == LogicalKeyboardKey.arrowDown) return AleraComposerMenuKey.next;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.tab)) {
      return AleraComposerMenuKey.pick;
    }
    return null;
  }

  /// The row [delta] steps from [index] in a list of [count] rows, wrapping
  /// at both ends.
  static int step(int index, int count, int delta) {
    if (count <= 0) return 0;
    return (index + delta) % count;
  }

  @override
  State<AleraComposerMenu> createState() => _AleraComposerMenuState();
}

class _AleraComposerMenuState extends State<AleraComposerMenu> {
  final ScrollController _scroll = ScrollController();
  String? _announced;

  int? get _active {
    final items = widget.items;
    if (items.isEmpty) return null;
    return widget.activeIndex.clamp(0, items.length - 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void didUpdateWidget(AleraComposerMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealActive();
      _announce();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealActive() {
    final active = _active;
    if (!mounted || active == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    final top = active * AleraTokens.menuRowHeight;
    final bottom = top + AleraTokens.menuRowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        math.min(bottom - position.viewportDimension, position.maxScrollExtent),
      );
    }
  }

  /// Tells a screen reader about the active row, or why there is none, once
  /// per change: the caret never leaves the field, so nothing else would.
  void _announce() {
    if (!mounted) return;
    final active = _active;
    final message = switch (active) {
      null when widget.loading => null,
      null => widget.emptyMessage,
      final int index => _describe(widget.items[index], index),
    };
    if (message == null || message == _announced) return;
    _announced = message;
    final view = View.maybeOf(context);
    if (view == null) return;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    unawaited(SemanticsService.sendAnnouncement(view, message, direction));
  }

  String _describe(AleraComposerMenuItem item, int index) {
    final parts = <String>[
      item.label,
      ?item.disabledReason ?? item.detail,
      '${index + 1} of ${widget.items.length}',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    final active = _active;
    final title = widget.title;
    final Widget body;
    if (items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Text(
          widget.loading ? widget.loadingMessage : widget.emptyMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      );
    } else {
      body = Flexible(
        child: ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
          itemExtent: AleraTokens.menuRowHeight,
          itemCount: items.length,
          itemBuilder: (context, index) => _AleraComposerMenuRow(
            key: ValueKey<String>('alera-composer-menu-${items[index].id}'),
            item: items[index],
            active: index == active,
            position: '${index + 1} of ${items.length}',
            onHover: widget.onActiveChanged == null || index == active
                ? null
                : () => widget.onActiveChanged!(index),
            onTap: () => widget.onPick(index),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticsLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: AleraTokens.shadowSoft,
                blurRadius: AleraTokens.space16,
                offset: Offset(0, AleraTokens.space8),
              ),
            ],
          ),
          child: Material(
            color: AleraTokens.surface,
            clipBehavior: .antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              side: const BorderSide(color: AleraTokens.border),
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.space12,
                      AleraTokens.space8,
                      AleraTokens.space12,
                      0,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        title,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _AleraComposerMenuRow({
  super.key,
  required final AleraComposerMenuItem item,
  required final bool active,
  required final String position,
  required final VoidCallback? onHover,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = item.enabled;
    final detail = item.disabledReason ?? item.detail;
    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: item.label,
      value: position,
      hint: detail,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: onHover == null ? null : (_) => onHover!(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
          child: AleraActiveRail(
            active: active,
            child: Material(
              color: active
                  ? AleraActiveRail.selectedColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              clipBehavior: .antiAlias,
              child: InkWell(
                // The text field keeps focus while the menu is open.
                canRequestFocus: false,
                onTap: enabled ? onTap : null,
                mouseCursor: enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                  ),
                  child: Row(
                    spacing: AleraTokens.space8,
                    children: <Widget>[
                      if (item.leading case final Widget leading)
                        SizedBox.square(
                          dimension: AleraTokens.iconLg,
                          child: Center(child: leading),
                        ),
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? AleraTokens.foreground
                                : AleraTokens.foregroundFaint,
                          ),
                        ),
                      ),
                      if (detail != null && detail.isNotEmpty)
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AleraTokens.foregroundFaint,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [menu] over [child] while [open], aligned to [child]'s width less
/// [inset], above it when it fits there and below it otherwise. The menu
/// never takes focus, and taps on it count as taps inside the text field, so
/// a desktop field does not lose focus when a row is clicked.
class const AleraComposerMenuAnchor({
  super.key,
  required final bool open,
  required final Widget menu,
  required final Widget child,
  final EdgeInsets inset = EdgeInsets.zero,
}) extends StatefulWidget {
  @override
  State<AleraComposerMenuAnchor> createState() =>
      _AleraComposerMenuAnchorState();
}

class _AleraComposerMenuAnchorState extends State<AleraComposerMenuAnchor> {
  // Shown for the anchor's whole life and empty while closed: [open] changes
  // during a build, when the portal must not be shown or hidden.
  final OverlayPortalController _portal = OverlayPortalController()..show();

  Widget _buildOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    if (!widget.open || info.childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final anchor = widget.inset.deflateRect(
      MatrixUtils.transformRect(
        info.childPaintTransform,
        Offset.zero & info.childSize,
      ),
    );
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _AleraComposerMenuLayout(anchor: anchor),
        child: TextFieldTapRegion(child: widget.menu),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: _buildOverlay,
    child: widget.child,
  );
}

class const _AleraComposerMenuLayout({required final Rect anchor})
    extends SingleChildLayoutDelegate {
  static const double _gap = AleraTokens.space4;
  static const double _margin = AleraTokens.space8;

  double _spaceAbove() => anchor.top - _gap - _margin;

  double _spaceBelow(Size overlay) =>
      overlay.height - _margin - anchor.bottom - _gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final overlay = constraints.biggest;
    final width = math.max(
      0.0,
      math.min(anchor.width, overlay.width - _margin * 2),
    );
    final height = math.max(0.0, math.max(_spaceAbove(), _spaceBelow(overlay)));
    return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = _spaceAbove();
    final opensUp = childSize.height <= above || above >= _spaceBelow(size);
    final y = opensUp
        ? anchor.top - _gap - childSize.height
        : anchor.bottom + _gap;
    final maxX = math.max(_margin, size.width - _margin - childSize.width);
    return Offset(anchor.left.clamp(_margin, maxX), y);
  }

  @override
  bool shouldRelayout(_AleraComposerMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}
