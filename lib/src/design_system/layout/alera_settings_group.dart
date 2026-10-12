import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

/// Titled group of setting rows: a heading with an optional description above
/// an [AleraPanel] that stacks [children] separated by hairline dividers.
///
/// A [collapsible] group toggles its panel from the heading, starting open
/// when [initiallyExpanded]. [trailing] sits at the end of the heading row,
/// outside the toggle, so an action there never collapses the group.
class const AleraSettingsGroup({
  super.key,
  required final String title,
  final String? description,
  required final List<Widget> children,
  final bool collapsible = false,
  final bool initiallyExpanded = true,
  final Widget? trailing,
}) extends StatefulWidget {
  @override
  State<AleraSettingsGroup> createState() => _AleraSettingsGroupState();
}

class _AleraSettingsGroupState extends State<AleraSettingsGroup> {
  late bool _expanded = widget.initiallyExpanded;

  bool get _showsPanel => !widget.collapsible || _expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading = Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (widget.collapsible) ...<Widget>[
              Icon(
                _expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                size: AleraTokens.iconMd,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
            ],
            Flexible(
              child: Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w600,
                ),
              ),
            ),
          ],
        ),
        if (widget.description case final description?) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
    if (widget.collapsible) {
      heading = Semantics(
        button: true,
        expanded: _expanded,
        child: HoverContainer(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AleraTokens.radiusSm,
          child: heading,
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: _showsPanel ? AleraTokens.space8 : 0,
          ),
          child: Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Expanded(child: heading),
              if (widget.trailing case final trailing?) ...<Widget>[
                const SizedBox(width: AleraTokens.space8),
                trailing,
              ],
            ],
          ),
        ),
        if (_showsPanel) AleraPanel(children: widget.children),
      ],
    );
  }
}
