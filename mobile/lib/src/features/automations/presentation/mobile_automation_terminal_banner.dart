import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Replaces the input bars of an automation terminal that is attached
/// read-only. Taking over is the only way to type, and it is explicit.
class const MobileAutomationTerminalBanner({
  required final String hostId,
  required final String tabId,
  required final String? runId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runId = this.runId;
    return Material(
      color: AleraTokens.surfaceVariant,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.spaceMd,
            vertical: AleraTokens.spaceSm,
          ),
          child: Row(
            children: <Widget>[
              const Icon(AleraIcons.visible, size: AleraTokens.iconSm),
              const SizedBox(width: AleraTokens.spaceSm),
              const Expanded(
                child: Text('An automation run is working here. Read only.'),
              ),
              TextButton(
                onPressed: runId == null || runId.isEmpty
                    ? null
                    : () => unawaited(
                        MobileAutomationActions(
                          ref,
                          hostId,
                          ScaffoldMessenger.of(context),
                        ).takeOver(runId, tabId: tabId),
                      ),
                child: const Text('Take Over'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
