part of 'resource_status_panel.dart';

// The tree itself: project, workspace, session and the shared metric row they
// all render through, plus Alera's own processes and the orphan footer.

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.project,
    required this.collapsed,
    required this.onToggle,
    required this.onOpenSession,
    required this.onKillSession,
  });

  final ResourceProjectGroup project;
  final bool collapsed;
  final ValueChanged<String>? onToggle;
  final ValueChanged<ResourceSessionRow> onOpenSession;
  final ValueChanged<ResourceSessionRow> onKillSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MetricRow(
          indent: 0,
          label: project.name,
          cpuPercent: project.cpuPercent,
          memoryBytes: project.memoryBytes,
          leading: Icon(
            collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
            size: 12,
            color: AleraTokens.foregroundFaint,
          ),
          bold: true,
          onTap: onToggle == null ? null : () => onToggle!(project.projectId),
        ),
        if (!collapsed)
          for (final workspace in project.workspaces)
            _WorkspaceSection(
              workspace: workspace,
              onOpenSession: onOpenSession,
              onKillSession: onKillSession,
            ),
      ],
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({
    required this.workspace,
    required this.onOpenSession,
    required this.onKillSession,
  });

  final ResourceWorkspaceRow workspace;
  final ValueChanged<ResourceSessionRow> onOpenSession;
  final ValueChanged<ResourceSessionRow> onKillSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MetricRow(
          indent: 1,
          label: workspace.name,
          suffix: workspace.remote ? 'remote' : null,
          cpuPercent: workspace.cpuPercent,
          memoryBytes: workspace.memoryBytes,
        ),
        for (final session in workspace.sessions)
          _SessionRow(
            session: session,
            onOpen: () => onOpenSession(session),
            onKill: () => onKillSession(session),
          ),
      ],
    );
  }
}

class _OrphanSection extends StatelessWidget {
  const _OrphanSection({required this.sessions, required this.onKillSession});

  final List<ResourceSessionRow> sessions;
  final ValueChanged<ResourceSessionRow> onKillSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MetricRow(
          indent: 0,
          label: 'Unattributed Terminals',
          cpuPercent: null,
          memoryBytes: null,
          bold: true,
        ),
        for (final session in sessions)
          _SessionRow(
            session: session,
            onOpen: null,
            onKill: () => onKillSession(session),
          ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.onOpen,
    required this.onKill,
  });

  final ResourceSessionRow session;
  final VoidCallback? onOpen;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    return _MetricRow(
      indent: 2,
      label: session.label,
      cpuPercent: session.cpuPercent,
      memoryBytes: session.memoryBytes,
      onTap: onOpen,
      leading: AleraStatusDot(active: session.running, size: 6),
      trailing: AleraIconButton(
        icon: AleraIcons.close,
        iconSize: 11,
        minSize: 18,
        tooltip: session.orphan
            ? 'Kill Orphan Terminal'
            : 'Close Terminal Session',
        onPressed: onKill,
      ),
      sparkline: session.history,
    );
  }
}

/// One row of the tree. Every level shares this so the metric columns keep the
/// same x position no matter how deep the row sits.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.indent,
    required this.label,
    required this.cpuPercent,
    required this.memoryBytes,
    this.leading,
    this.trailing,
    this.suffix,
    this.onTap,
    this.bold = false,
    this.sparkline = const <int>[],
  });

  final int indent;
  final String label;
  final double? cpuPercent;
  final int? memoryBytes;
  final Widget? leading;
  final Widget? trailing;
  final String? suffix;
  final VoidCallback? onTap;
  final bool bold;
  final List<int> sparkline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: EdgeInsets.only(
        left: AleraTokens.space12 + (indent * AleraTokens.space12),
        right: AleraTokens.space12,
        top: AleraTokens.space4,
        bottom: AleraTokens.space4,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AleraTokens.space6),
          ],
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (suffix != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    suffix!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (sparkline.length > 1) ...<Widget>[
            AleraSparkline(samples: sparkline),
            const SizedBox(width: AleraTokens.space8),
          ],
          _MetricCell(value: formatResourceCpu(cpuPercent)),
          _MetricCell(value: formatResourceMemory(memoryBytes)),
          ?trailing,
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: row,
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _metricColumnWidth,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: AleraTokens.monoStyle.copyWith(fontSize: 10),
      ),
    );
  }
}

/// Alera's own processes, kept apart from the workspace tree so the app and the
/// sidecar never look like somebody's terminal.
class _AleraSection extends StatelessWidget {
  const _AleraSection({required this.snapshot});

  final ResourceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final app = snapshot.appProcess;
    final host = snapshot.hostProcess;
    if (app == null && host == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        _MetricRow(
          indent: 0,
          label: 'Alera',
          cpuPercent: (app?.cpuPercent ?? 0) + (host?.cpuPercent ?? 0),
          memoryBytes: (app?.memoryBytes ?? 0) + (host?.memoryBytes ?? 0),
          bold: true,
        ),
        if (app != null)
          _MetricRow(
            indent: 1,
            label: 'App',
            cpuPercent: app.cpuPercent,
            memoryBytes: app.memoryBytes,
            sparkline: app.history,
          ),
        if (host != null)
          _MetricRow(
            indent: 1,
            label: 'Runtime Host',
            cpuPercent: host.cpuPercent,
            memoryBytes: host.memoryBytes,
            sparkline: host.history,
          ),
      ],
    );
  }
}

class _OrphanFooter extends StatelessWidget {
  const _OrphanFooter({required this.count, required this.onKillOrphans});

  final int count;
  final VoidCallback onKillOrphans;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$count Orphan Terminal${count == 1 ? '' : 's'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AleraTokens.warning),
            ),
          ),
          TextButton(onPressed: onKillOrphans, child: const Text('Kill All')),
        ],
      ),
    );
  }
}
