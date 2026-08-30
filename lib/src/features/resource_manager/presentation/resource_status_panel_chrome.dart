part of 'resource_status_panel.dart';

// Panel chrome: the title bar, the host notice, the totals strip and the
// sortable column header. Everything here frames the tree without knowing what
// is in it.

class const _PanelHeader() extends StatelessWidget {
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
class const _HostUnreachableNotice() extends StatelessWidget {
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

class const _TotalsRow({required final ResourceSnapshot snapshot})
    extends StatelessWidget {
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
                overflow: .ellipsis,
                style: AleraTokens.monoStyle.copyWith(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _TotalsValue({
  required final String label,
  required final String value,
  required final String tooltip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: .min,
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

class const _SortHeader({
  required final ResourceSortColumn sortColumn,
  required final ValueChanged<ResourceSortColumn> onSortColumnChanged,
}) extends StatelessWidget {
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
              column: .name,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: .centerLeft,
            ),
          ),
          SizedBox(
            width: _metricColumnWidth,
            child: _SortButton(
              label: 'CPU',
              column: .cpu,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: .centerRight,
            ),
          ),
          SizedBox(
            width: _metricColumnWidth,
            child: _SortButton(
              label: 'Memory',
              column: .memory,
              sortColumn: sortColumn,
              onPressed: onSortColumnChanged,
              alignment: .centerRight,
            ),
          ),
          const SizedBox(width: _actionColumnWidth),
        ],
      ),
    );
  }
}

class const _SortButton({
  required final String label,
  required final ResourceSortColumn column,
  required final ResourceSortColumn sortColumn,
  required final ValueChanged<ResourceSortColumn> onPressed,
  required final Alignment alignment,
}) extends StatelessWidget {
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
