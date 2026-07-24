import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:flutter/material.dart';

const double runtimeHostPanelWidth = 240;
const double runtimeHostPanelMaxHeight = 360;

/// Label column of the status rows. Wide enough for "Bundled Version", the
/// longest label, so it never runs into the value beside it.
const double _statusLabelWidth = 116;

/// Compact status-bar chip for the local runtime host.
class RuntimeHostStatusChip extends StatelessWidget {
  const RuntimeHostStatusChip({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.onPressed,
  });

  final RuntimeHostStatusSnapshot? snapshot;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = _chipLabel(snapshot, loading: loading);
    final color = _chipColor(snapshot, loading: loading);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        // InkWell defaults to adaptiveClickable, which stays an arrow off the
        // web. The status bar uses the hand cursor for every clickable chip.
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Container(
          height: AleraTokens.statusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(AleraIcons.host, size: 13, color: color),
              const SizedBox(width: AleraTokens.space6),
              Text(
                label,
                style: AleraTokens.monoStyle.copyWith(
                  fontSize: 10,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive panel opened from the runtime status-bar chip.
class RuntimeHostStatusPanel extends StatelessWidget {
  const RuntimeHostStatusPanel({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.onRefresh,
    required this.onStart,
    required this.onStop,
    required this.onUpdate,
    this.busy = false,
  });

  final RuntimeHostStatusSnapshot? snapshot;
  final bool loading;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = snapshot;
    final running = status?.running == true;
    final updateAvailable = status?.updateAvailable == true;
    // Stopping with live work attached kills sessions and agents, so the button
    // carries the destructive styling before the force confirmation appears.
    final stopIsDestructive =
        (status?.activeSessions ?? 0) > 0 || (status?.activeAgents ?? 0) > 0;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: runtimeHostPanelWidth,
        constraints: const BoxConstraints(maxHeight: runtimeHostPanelMaxHeight),
        decoration: BoxDecoration(
          color: AleraTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Runtime', style: theme.textTheme.titleSmall),
                const SizedBox(height: AleraTokens.space8),
                _StatusRow(
                  label: 'Status',
                  value: loading
                      ? 'Checking'
                      : running
                      ? 'Running'
                      : 'Stopped',
                  valueColor: !loading && running ? AleraTokens.success : null,
                ),
                _StatusRow(
                  label: 'Host Version',
                  value: runtimeHostVersionLabel(status?.runtimeHostVersion),
                ),
                _StatusRow(
                  label: 'Bundled Version',
                  value: runtimeHostVersionLabel(status?.bundledVersion),
                ),
                if (status?.persistent == true)
                  const _StatusRow(label: 'Lifecycle', value: 'Persistent'),
                _StatusRow(
                  label: 'Sessions',
                  value: '${status?.activeSessions ?? 0}',
                ),
                _StatusRow(
                  label: 'Agents',
                  value: '${status?.activeAgents ?? 0}',
                ),
                if (status?.error case final error?) ...<Widget>[
                  const SizedBox(height: AleraTokens.space8),
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.error,
                    ),
                  ),
                ],
                const SizedBox(height: AleraTokens.space12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: busy ? null : onRefresh,
                      child: const Text('Refresh'),
                    ),
                    if (!running)
                      FilledButton(
                        onPressed: busy ? null : onStart,
                        child: const Text('Start'),
                      ),
                    if (running)
                      OutlinedButton(
                        onPressed: busy ? null : onStop,
                        style: stopIsDestructive
                            ? OutlinedButton.styleFrom(
                                foregroundColor: AleraTokens.error,
                                side: const BorderSide(
                                  color: AleraTokens.error,
                                ),
                              )
                            : null,
                        child: const Text('Stop'),
                      ),
                    if (updateAvailable)
                      FilledButton(
                        onPressed: busy ? null : onUpdate,
                        child: const Text('Update Runtime'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _statusLabelWidth,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              value,
              style: AleraTokens.monoStyle.copyWith(
                fontSize: 11,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _chipLabel(
  RuntimeHostStatusSnapshot? snapshot, {
  required bool loading,
}) {
  if (loading && snapshot == null) {
    return 'Runtime';
  }
  if (snapshot?.error != null && snapshot?.running != true) {
    return 'Runtime Error';
  }
  if (snapshot?.updateAvailable == true) {
    return 'Update Available';
  }
  if (snapshot?.running == true) {
    final version = snapshot?.runtimeHostVersion;
    if (version != null && version.trim().isNotEmpty) {
      return 'Runtime ${runtimeHostVersionLabel(version)}';
    }
    return 'Runtime Running';
  }
  return 'Runtime Stopped';
}

/// Renders a sidecar version as `v1.2.3`, keeping an existing `v` prefix.
String runtimeHostVersionLabel(String? version) {
  final value = version?.trim() ?? '';
  if (value.isEmpty) {
    return '-';
  }
  return value.startsWith('v') || value.startsWith('V') ? value : 'v$value';
}

Color _chipColor(RuntimeHostStatusSnapshot? snapshot, {required bool loading}) {
  if (snapshot?.error != null && snapshot?.running != true) {
    return AleraTokens.error;
  }
  if (snapshot?.updateAvailable == true) {
    return AleraTokens.warning;
  }
  if (snapshot?.running == true) {
    return AleraTokens.success;
  }
  if (loading) {
    return AleraTokens.foregroundMuted;
  }
  return AleraTokens.foregroundFaint;
}
