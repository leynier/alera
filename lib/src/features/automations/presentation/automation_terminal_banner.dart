import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown above an automation-owned terminal that is attached read-only.
/// Taking over is the only way to type into it, and it is always explicit.
class const AutomationTerminalBanner({
  required final String tabId,
  required final String? runId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runId = this.runId;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.visible,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              'An automation run is working here. Read only.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: runId == null
                ? null
                : () => unawaited(
                    AutomationActions(ref)
                        .takeOverTab(runId: runId, tabId: tabId),
                  ),
            child: const Text('Take Over · Stops Automatic Recovery'),
          ),
        ],
      ),
    );
  }
}
