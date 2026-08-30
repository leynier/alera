part of 'resource_status_panel.dart';

// Panel chrome: the title bar, the host notice, the totals strip and the
// sortable column header. Everything here frames the tree without knowing what
// is in it.

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.resources,
            size: 13,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Text(
            'Resource Manager',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AleraTokens.foreground),
          ),
        ],
      ),
    );
  }
}

/// The host is unreachable, so the panel points at the runtime host control
/// rather than duplicating its Start/Stop/Restart flow.
class _HostUnreachableNotice extends StatelessWidget {
  const _HostUnreachableNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      color: AleraTokens.warning.withValues(alpha: 0.12),
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.warning, size: 13, color: AleraTokens.warning),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              'The runtime host is not responding. Use the host chip to '
              'restart it.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.snapshot});

  final ResourceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final warming = !snapshot.hasReading;
    final cpu = warming
        ? null
        : machineCpuShare(snapshot.totalCpuPercent, snapshot.host.cpuCoreCount);
    final memory = warming ? null : snapshot.totalMemoryBytes;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          _TotalsValue(
            label: 'CPU',
            value: formatResourceCpu(cpu),
            tooltip:
                'Total CPU across Alera and every terminal it spawned, as a '
                'share of everything this machine can run at once.',
          ),
          const SizedBox(width: AleraTokens.space16),
          _TotalsValue(
            label: 'Memory',
            value: formatResourceMemory(memory),
            tooltip:
                'Resident memory of Alera, the runtime host, and every '
                'terminal process.',
          ),
          const Spacer(),
          // Flexible with an ellipsis so a wide reading degrades instead of
          // overflowing the fixed-width panel.
          Flexible(
            child: Tooltip(
              message: 'Share of the machine memory these processes hold.',
              child: Text(
                formatResourceShareOfSystem(
                  memory,
                  snapshot.host.totalMemoryBytes,
                ),
                overflow: TextOverflow.ellipsis,
                style: AleraTokens.monoStyle.copyWith(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsValue extends StatelessWidget {
  const _TotalsValue({
    required this.label,
    required this.value,
    required this.tooltip,
  });

  final String label;
  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
          const SizedBox(width: AleraTokens.space6),
          Text(
            value,
            style: AleraTokens.monoStyle.copyWith(
              fontSize: 11,
              color: AleraTokens.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.sortColumn,
    required this.onSortColumnChanged,
  });

  final ResourceSortColumn sortColumn;
  final ValueChanged<ResourceSortColumn> onSortColumnChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space4,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SortButton(
              label: 'Name',
              column: ResourceSortColumn.name,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: Alignment.centerLeft,
            ),
          ),
          SizedBox(
            width: _metricColumnWidth,
            child: _SortButton(
              label: 'CPU',
              column: ResourceSortColumn.cpu,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: Alignment.centerRight,
            ),
          ),
          SizedBox(
            width: _metricColumnWidth,
            child: _SortButton(
              label: 'Memory',
              column: ResourceSortColumn.memory,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: Alignment.centerRight,
            ),
          ),
          const SizedBox(width: _actionColumnWidth),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.column,
    required this.sortColumn,
    required this.onPressed,
    required this.alignment,
  });

  final String label;
  final ResourceSortColumn column;
  final ResourceSortColumn sortColumn;
  final ValueChanged<ResourceSortColumn> onPressed;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final selected = column == sortColumn;
    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: 'Sort By $label',
        child: InkWell(
          onTap: () => onPressed(column),
          mouseCursor: WidgetStateMouseCursor.clickable,
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundFaint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
