import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_defaults_group.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_launch_groups.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_models_group.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_status_summary.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Everything the detail column shows for the selected instance. The pane
/// owns the state; this widget only lays it out.
class const AgentProviderDetail({
  super.key,
  required final String title,
  required final String defaultLabel,
  required final AgentProviderStatus status,
  required final DateTime now,
  required final AgentProviderDraftEditing editing,
  required final AgentProviderDefaultsGroup defaults,
  required final AgentProviderModelsGroup models,
  required final bool dirty,
  required final bool saving,
  required final VoidCallback onSave,
  required final VoidCallback onRevert,
  final AgentChatProviderInstance? catalog,
  final bool canRunSetup = true,
  final String? setupHostLabel,
  final String? setupUnavailableReason,
  final ValueChanged<AgentChatProviderSetupCommand>? onRunSetup,
  final String? launchReadOnlyReason,
  final String? changedElsewhereMessage,
  final String? error,
  final List<String> problems = const <String>[],
  final String? removeLabel,
  final VoidCallback? onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final draft = editing.draft;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AleraTokens.space24),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                AgentProviderStatusSummary(
                  provider: draft.provider,
                  providerInstanceId: draft.providerInstanceId,
                  title: title,
                  status: status,
                  now: now,
                  catalog: catalog,
                  canRunSetup: canRunSetup,
                  setupHostLabel: setupHostLabel,
                  setupUnavailableReason: setupUnavailableReason,
                  onRunSetup: onRunSetup,
                ),
                if (changedElsewhereMessage case final message?) ...<Widget>[
                  const SizedBox(height: AleraTokens.space12),
                  AleraInlineNotice(message: message, tone: .warning),
                ],
                if (launchReadOnlyReason case final reason?) ...<Widget>[
                  const SizedBox(height: AleraTokens.space12),
                  AleraInlineNotice(message: reason),
                ],
                const SizedBox(height: AleraTokens.space24),
                defaults,
                const SizedBox(height: AleraTokens.space24),
                AgentProviderIdentityGroup(
                  editing: editing,
                  defaultLabel: defaultLabel,
                ),
                const SizedBox(height: AleraTokens.space24),
                AgentProviderLaunchGroup(editing: editing),
                const SizedBox(height: AleraTokens.space24),
                AgentProviderEnvironmentGroup(editing: editing),
                const SizedBox(height: AleraTokens.space24),
                models,
                if (onRemove != null && removeLabel != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: saving ? null : onRemove,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AleraTokens.error,
                      ),
                      child: Text(removeLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (dirty || error != null)
          _SaveBar(
            dirty: dirty,
            saving: saving,
            isNew: draft.isNew,
            error: error,
            problems: problems,
            onSave: onSave,
            onRevert: onRevert,
          ),
      ],
    );
  }
}

class const _SaveBar({
  required final bool dirty,
  required final bool saving,
  required final bool isNew,
  required final String? error,
  required final List<String> problems,
  required final VoidCallback onSave,
  required final VoidCallback onRevert,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message =
        error ??
        problems.firstOrNull ??
        (isNew
            ? 'This provider is not saved yet.'
            : 'Unsaved changes apply to the next chat start.');
    final tone = error != null || problems.isNotEmpty
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: tone),
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
            TextButton(
              onPressed: saving || !dirty ? null : onRevert,
              child: Text(isNew ? 'Discard' : 'Revert'),
            ),
            const SizedBox(width: AleraTokens.space8),
            FilledButton(
              onPressed: saving || !dirty || problems.isNotEmpty
                  ? null
                  : onSave,
              child: saving
                  ? const SizedBox.square(
                      dimension: AleraTokens.iconMd,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeSm,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
