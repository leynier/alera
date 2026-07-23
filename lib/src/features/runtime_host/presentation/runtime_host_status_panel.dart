import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

const double runtimeHostPanelWidth = 360;
const double runtimeHostPanelMaxHeight = 520;

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
    required this.stopRuntimeOnAppQuit,
    required this.emptyShutdownDelaySeconds,
    required this.detachedSessionShutdownDelaySeconds,
    required this.onRefresh,
    required this.onStart,
    required this.onStop,
    required this.onUpdate,
    required this.onStopRuntimeOnAppQuitChanged,
    required this.onEmptyShutdownDelayChanged,
    required this.onDetachedSessionShutdownDelayChanged,
    this.busy = false,
  });

  final RuntimeHostStatusSnapshot? snapshot;
  final bool loading;
  final bool busy;
  final bool stopRuntimeOnAppQuit;
  final int emptyShutdownDelaySeconds;
  final int detachedSessionShutdownDelaySeconds;
  final VoidCallback onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onUpdate;
  final ValueChanged<bool> onStopRuntimeOnAppQuitChanged;
  final ValueChanged<int> onEmptyShutdownDelayChanged;
  final ValueChanged<int> onDetachedSessionShutdownDelayChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = snapshot;
    final running = status?.running == true;
    final updateAvailable = status?.updateAvailable == true;
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
                ),
                _StatusRow(
                  label: 'Host Version',
                  value: status?.runtimeHostVersion ?? '-',
                ),
                _StatusRow(
                  label: 'Bundled Version',
                  value: status?.bundledVersion ?? '-',
                ),
                if (status?.runtimeHostCommit != null)
                  _StatusRow(
                    label: 'Host Commit',
                    value: status!.runtimeHostCommit!,
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
                        child: const Text('Stop'),
                      ),
                    if (updateAvailable)
                      FilledButton(
                        onPressed: busy ? null : onUpdate,
                        child: const Text('Update Runtime'),
                      ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space16),
                Text('Lifecycle', style: theme.textTheme.titleSmall),
                const SizedBox(height: AleraTokens.space8),
                SettingsSwitchRow(
                  title: 'Stop Runtime When App Quits',
                  description:
                      'Shut down the local runtime when the last Alera window closes.',
                  value: stopRuntimeOnAppQuit,
                  onChanged: onStopRuntimeOnAppQuitChanged,
                ),
                SettingsIntegerRow(
                  title: 'Empty Host Shutdown',
                  description:
                      'Seconds to keep the host alive after the app closes with no running sessions.',
                  value: emptyShutdownDelaySeconds,
                  min: 5,
                  max: 3600,
                  step: 5,
                  suffix: 's',
                  onChanged: onEmptyShutdownDelayChanged,
                ),
                SettingsIntegerRow(
                  title: 'Detached Session Shutdown',
                  description:
                      'Seconds to keep detached running sessions alive after the app closes.',
                  value: detachedSessionShutdownDelaySeconds,
                  min: 5,
                  max: 86400,
                  step: 60,
                  suffix: 's',
                  onChanged: onDetachedSessionShutdownDelayChanged,
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
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AleraTokens.monoStyle.copyWith(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _chipLabel(RuntimeHostStatusSnapshot? snapshot, {required bool loading}) {
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
    if (version != null && version.isNotEmpty) {
      return 'Runtime $version';
    }
    return 'Runtime Running';
  }
  return 'Runtime Stopped';
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
