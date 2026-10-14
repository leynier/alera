import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_entries.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_option_specs.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The first free `<provider>-<n>` id, so a second Claude reads
/// `claudeAgent-2` until the person names it.
String agentProviderSuggestedInstanceId(
  String provider,
  Iterable<String> takenIds,
) {
  final taken = takenIds.toSet();
  for (var index = 2; ; index++) {
    final candidate = '$provider-$index';
    if (!taken.contains(candidate)) {
      return candidate;
    }
  }
}

/// Asks for the provider kind, instance id and label of a new instance and
/// returns an unsaved draft; nothing reaches the host until Save.
Future<AgentProviderInstanceDraft?> showAddAgentProviderDialog(
  BuildContext context, {
  required Set<String> takenIds,
}) => showDialog<AgentProviderInstanceDraft>(
  context: context,
  builder: (_) => _AddProviderDialog(takenIds: takenIds),
);

class const _AddProviderDialog({required final Set<String> takenIds})
    extends StatefulWidget {
  @override
  State<_AddProviderDialog> createState() => _AddProviderDialogState();
}

class _AddProviderDialogState extends State<_AddProviderDialog> {
  String _provider = agentProviderKinds.first;
  late final TextEditingController _id = TextEditingController(
    text: agentProviderSuggestedInstanceId(_provider, widget.takenIds),
  );
  final TextEditingController _label = TextEditingController();
  late String _suggestedId = _id.text;

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    super.dispose();
  }

  String? get _idError {
    final id = _id.text.trim();
    if (widget.takenIds.contains(id)) {
      return 'This host already has an instance named $id.';
    }
    if (agentProviderKinds.contains(id)) {
      return 'Built-in instances already use that id.';
    }
    if (!agentProviderInstanceIdPattern.hasMatch(id)) {
      return 'Start with a letter; use letters, digits, dots, dashes and '
          'underscores.';
    }
    return null;
  }

  void _selectProvider(String provider) {
    setState(() {
      // Keep an id the person typed; only replace the one we suggested.
      if (_id.text.trim() == _suggestedId) {
        _suggestedId = agentProviderSuggestedInstanceId(
          provider,
          widget.takenIds,
        );
        _id.text = _suggestedId;
      }
      _provider = provider;
    });
  }

  void _submit() {
    if (_idError != null) {
      return;
    }
    Navigator.of(context).pop(
      AgentProviderInstanceDraft.create(
        providerInstanceId: _id.text.trim(),
        provider: _provider,
        label: _label.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 460,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDialogHeader(
            title: 'Add Provider',
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space20),
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[_id, _label]),
              builder: (context, _) => Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  Text(
                    'Run a second configuration of a provider, such as a '
                    'work account or a custom executable.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space16),
                  AleraDropdownField<String>(
                    labelText: 'Provider',
                    value: _provider,
                    entries: <AleraDropdownFieldEntry<String>>[
                      for (final kind in agentProviderKinds)
                        AleraDropdownFieldEntry<String>(
                          value: kind,
                          label: agentProviderDefaultLabel(kind),
                        ),
                    ],
                    onChanged: _selectProvider,
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  AleraTextField(
                    controller: _id,
                    labelText: 'Instance Id',
                    errorText: _id.text.isEmpty ? null : _idError,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  AleraTextField(
                    controller: _label,
                    labelText: 'Label',
                    hintText: agentProviderDefaultLabel(_provider),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AleraTokens.space20),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _idError == null ? _submit : null,
                          child: const Text('Add Provider'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows what removing [label] affects before it happens. Open chats keep
/// their history and are not closed; they need another provider before
/// their next turn. Returns whether the person confirmed.
Future<bool> confirmAgentProviderRemoval(
  BuildContext context, {
  required String label,
  required bool builtIn,
  required AgentChatProviderRemovalImpact impact,
}) async {
  final count = impact.count;
  final verb = builtIn ? 'Reset' : 'Remove';
  final consequence = builtIn
      ? '$label goes back to its default launch settings, custom models '
            'and enabled state.'
      : '$label is removed from this host and from the chat picker.';
  // A reset keeps the built-in instance, so its chats keep working; only
  // removing an added instance leaves chats without a provider.
  final chats = builtIn
      ? 'Open chats keep it and use the defaults from their next start.'
      : switch (count) {
          0 => 'No open chat uses it.',
          1 =>
            '1 open chat uses it (${impact.openChats.first.title}). It keeps '
                'its history and needs another provider before its next turn.',
          _ =>
            '$count open chats use it, including '
                '${impact.openChats.take(3).map((chat) => chat.title).join(', ')}. '
                'They keep their history and need another provider before '
                'their next turn.',
        };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: builtIn ? 'Reset $label?' : 'Remove $label?',
      message: '$consequence $chats',
      confirmLabel: verb,
      destructive: true,
    ),
  );
  return confirmed ?? false;
}
