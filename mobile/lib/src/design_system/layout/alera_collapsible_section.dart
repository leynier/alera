import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Section with a chevron header that expands and collapses [child] over
/// `durationMid`. An optional [description] sits under the [title] and an
/// optional [trailing] widget (a count badge, an action) at the end of the
/// header. The header is at least a full tap target tall.
///
/// Controlled when [expanded] is set: the header only reports the requested
/// state through [onExpandedChanged]. Otherwise it keeps its own state,
/// starting from [initiallyExpanded]. The collapsed [child] leaves the tree
/// once the animation ends.
///
/// Phone copy of the desktop `AleraCollapsibleSection`.
class const AleraCollapsibleSection({
  super.key,
  required final String title,
  required final Widget child,
  final String? description,
  final Widget? trailing,
  final bool? expanded,
  final ValueChanged<bool>? onExpandedChanged,
  final bool initiallyExpanded = false,
}) extends StatefulWidget {
  @override
  State<AleraCollapsibleSection> createState() =>
      _AleraCollapsibleSectionState();
}

class _AleraCollapsibleSectionState extends State<AleraCollapsibleSection>
    with SingleTickerProviderStateMixin {
  static const double _quarterTurn = 0.25;

  late bool _localExpanded = widget.initiallyExpanded;
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: AleraTokens.durationMid,
    value: _isExpanded ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _chevronTurns = Tween<double>(
    begin: 0,
    end: _quarterTurn,
  ).animate(_curve);

  bool get _isExpanded => widget.expanded ?? _localExpanded;

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(AleraCollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animate();
  }

  @override
  void dispose() {
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  void _animate() {
    if (_isExpanded) {
      _animation.forward();
    } else {
      _animation.reverse();
    }
  }

  void _toggle() {
    final next = !_isExpanded;
    widget.onExpandedChanged?.call(next);
    if (widget.expanded == null) {
      setState(() => _localExpanded = next);
      _animate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = _isExpanded;
    final showBody = expanded || !_animation.isDismissed;
    final description = widget.description;
    final header = Semantics(
      expanded: expanded,
      button: true,
      child: InkWell(
        onTap: _toggle,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space4,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                RotationTransition(
                  turns: _chevronTurns,
                  child: const Icon(
                    AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: .w600,
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AleraTokens.space2,
                          ),
                          child: Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing case final trailing?) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        header,
        if (showBody)
          ClipRect(
            child: SizeTransition(
              sizeFactor: _curve,
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: widget.child,
              ),
            ),
          ),
      ],
    );
  }
}
