import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/presentation/automation_destructive_actions.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _MoreAction { clone, pauseAndCancel, trash }

/// Clone, Pause And Cancel Runs and Move To Trash, shared by catalog rows and
/// the detail header. The two destructive ones ask first.
class const AutomationMoreMenuButton({
  required final AutomationRecord automation,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automation = this.automation;
    return AleraIconButton(
      tooltip: 'More Actions',
      icon: AleraIcons.more,
      onPressed: () => unawaited(() async {
        final box = context.findRenderObject()! as RenderBox;
        final overlay =
            Navigator.of(context).overlay!.context.findRenderObject()!
                as RenderBox;
        final origin = box.localToGlobal(
          Offset(0, box.size.height),
          ancestor: overlay,
        );
        final action = await showMenu<_MoreAction>(
          context: context,
          position: RelativeRect.fromRect(
            origin & Size.zero,
            Offset.zero & overlay.size,
          ),
          items: <PopupMenuEntry<_MoreAction>>[
            const AleraDropdownEntry(
              value: _MoreAction.clone,
              leading: Icon(AleraIcons.copy, size: AleraTokens.iconMd),
              label: 'Clone',
            ),
            if (automation.state == 'active')
              const AleraDropdownEntry(
                value: _MoreAction.pauseAndCancel,
                leading: Icon(AleraIcons.blocked, size: AleraTokens.iconMd),
                label: 'Pause And Cancel Runs',
              ),
            if (!automation.isTrashed)
              const AleraDropdownEntry(
                value: _MoreAction.trash,
                leading: Icon(AleraIcons.delete, size: AleraTokens.iconMd),
                label: 'Move To Trash',
              ),
          ],
        );
        if (action == null || !context.mounted) return;
        await switch (action) {
          _MoreAction.clone => showAutomationComposerDialog(
            context,
            ref,
            request: AutomationAuthoringRequest(cloneId: automation.id),
          ),
          _MoreAction.pauseAndCancel => confirmAutomationPauseAndCancel(
            context,
            ref,
            automation,
          ),
          _MoreAction.trash => confirmAutomationTrash(context, ref, automation),
        };
      }()),
    );
  }
}
