import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_sparkline.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/resource_manager/domain/machine_cpu_share.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_value_format.dart';
import 'package:flutter/material.dart';

part 'resource_status_panel_chrome.dart';
part 'resource_status_panel_rows.dart';

/// Wide enough that reserving [_actionColumnWidth] on every row costs the name
/// column nothing next to a panel that carried no row actions.
const double resourcePanelWidth = 400 + _actionColumnWidth;
const double resourcePanelMaxHeight = 420;

/// Width of the CPU and memory columns. Fixed so the numbers line up down the
/// tree even though rows sit at different indent depths.
const double _metricColumnWidth = 68;

/// Icon size of a row's trailing action, and its real footprint: `IconButton`'s
/// compact visual density shrinks the button's own minimum away, so it collapses
/// onto the icon.
const double _actionIconSize = 11;

/// Width of the trailing action slot. Reserved on every row and on the sort
/// header, even where there is no action, so the metric columns keep the same
/// x position on the session rows that do carry one.
const double _actionColumnWidth = _actionIconSize + AleraTokens.space6;

/// Presentational resource panel. Data and callbacks arrive as parameters so it
/// stays previewable and testable without a runtime host.
class ResourceStatusPanel extends StatelessWidget {
  const ResourceStatusPanel({
    super.key,
    required this.snapshot,
    required this.tree,
    required this.sortColumn,
    required this.onSortColumnChanged,
    required this.onOpenSession,
    required this.onKillSession,
    required this.onKillOrphans,
    this.collapsedProjectIds = const <String>{},
    this.onToggleProject,
    this.hostUnreachable = false,
  });

  final ResourceSnapshot snapshot;
  final ResourceTree tree;
  final ResourceSortColumn sortColumn;
  final ValueChanged<ResourceSortColumn> onSortColumnChanged;
  final ValueChanged<ResourceSessionRow> onOpenSession;
  final ValueChanged<ResourceSessionRow> onKillSession;
  final VoidCallback onKillOrphans;
  final Set<String> collapsedProjectIds;
  final ValueChanged<String>? onToggleProject;
  final bool hostUnreachable;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: resourcePanelWidth,
      constraints: const BoxConstraints(maxHeight: resourcePanelMaxHeight),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _PanelHeader(),
            if (hostUnreachable) const _HostUnreachableNotice(),
            _TotalsRow(snapshot: snapshot),
            _SortHeader(
              sortColumn: sortColumn,
              onSortColumnChanged: onSortColumnChanged,
            ),
            Flexible(child: _PanelBody(panel: this)),
            if (tree.orphanSessions.isNotEmpty)
              _OrphanFooter(
                count: tree.orphanSessions.length,
                onKillOrphans: onKillOrphans,
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.panel});

  final ResourceStatusPanel panel;

  @override
  Widget build(BuildContext context) {
    final snapshot = panel.snapshot;
    if (panel.tree.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space24),
        child: AleraEmptyState(
          icon: AleraIcons.resources,
          message: switch (snapshot) {
            ResourceSnapshot(error: final String error) => error,
            ResourceSnapshot(warming: true) => 'Measuring Resource Usage',
            _ => 'No Terminal Sessions Are Running',
          },
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final project in panel.tree.projects)
            _ProjectSection(
              project: project,
              collapsed: panel.collapsedProjectIds.contains(project.projectId),
              onToggle: panel.onToggleProject,
              onOpenSession: panel.onOpenSession,
              onKillSession: panel.onKillSession,
            ),
          if (panel.tree.orphanSessions.isNotEmpty)
            _OrphanSection(
              sessions: panel.tree.orphanSessions,
              onKillSession: panel.onKillSession,
            ),
          _AleraSection(snapshot: snapshot),
        ],
      ),
    );
  }
}
