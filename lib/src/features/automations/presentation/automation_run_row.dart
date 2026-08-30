import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';

class const AutomationRunRow({
  required final AutomationRunRecord run,
  final VoidCallback? onCancel,
  final VoidCallback? onResumeWaiting,
  final VoidCallback? onExtendWaiting,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _runIcon(run.status),
        size: 16,
        color: _runColor(run.status),
      ),
      title: Text('#${run.number} · ${run.status}'),
      subtitle: Text(run.summary ?? run.error ?? run.trigger),
      trailing:
          onCancel == null && onResumeWaiting == null && onExtendWaiting == null
          ? null
          : Wrap(
              spacing: AleraTokens.space4,
              children: <Widget>[
                if (onResumeWaiting != null)
                  TextButton(
                    onPressed: onResumeWaiting,
                    child: const Text('Resume'),
                  ),
                if (onExtendWaiting != null)
                  TextButton(
                    onPressed: onExtendWaiting,
                    child: const Text('Extend'),
                  ),
                if (onCancel != null)
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
    );
  }

  IconData _runIcon(String status) => switch (status) {
    'success' => AleraIcons.success,
    'failure' || 'timeout' => AleraIcons.error,
    'blocked' || 'cancelled' => AleraIcons.blocked,
    _ => AleraIcons.loading,
  };

  Color _runColor(String status) => switch (status) {
    'success' => AleraTokens.success,
    'failure' || 'timeout' => AleraTokens.error,
    'blocked' || 'cancelled' => AleraTokens.warning,
    _ => AleraTokens.info,
  };
}
