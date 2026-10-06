import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<Duration> inboxExpiryChoices = <Duration>[
  Duration(hours: 1),
  Duration(hours: 5),
  Duration(days: 1),
  Duration(days: 7),
];

/// Defaults to the runtime's own default so an unchanged choice sends nothing.
const Duration inboxDefaultExpiry = Duration(hours: 5);

String _expiryLabel(Duration value) => value.inDays > 0
    ? '${value.inDays} Day${value.inDays == 1 ? '' : 's'}'
    : '${value.inHours} Hour${value.inHours == 1 ? '' : 's'}';

Future<void> showInboxComposerDialog(
  BuildContext context, {
  String? targetHandle,
}) => showDialog<void>(
  context: context,
  builder: (_) => InboxComposerDialog(initialTarget: targetHandle),
);

/// Asks a running agent a new question from the shared `ext:user` inbox.
class InboxComposerDialog extends ConsumerStatefulWidget {
  const InboxComposerDialog({super.key, this.initialTarget});

  final String? initialTarget;

  @override
  ConsumerState<InboxComposerDialog> createState() =>
      _InboxComposerDialogState();
}

class _InboxComposerDialogState extends ConsumerState<InboxComposerDialog> {
  final _inbox = TextEditingController(text: inboxUserAddress);
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _target;
  Duration _expiry = inboxDefaultExpiry;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
  }

  @override
  void dispose() {
    _inbox.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && _target != null && _body.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final threadId = await ref
          .read(inboxRepositoryProvider)
          .ask(
            InboxAskRequest(
              body: _body.text.trim(),
              inbox: _inbox.text.trim().isEmpty ? null : _inbox.text.trim(),
              to: _target,
              subject: _subject.text,
              expiresIn: _expiry == inboxDefaultExpiry ? null : _expiry,
            ),
          );
      if (!mounted) return;
      final navigation = ref.read(inboxNavigationProvider.notifier);
      navigation.filterInbox(null);
      navigation.selectThread(threadId.isEmpty ? null : threadId);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = inboxErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(inboxTargetsProvider);
    final workspaceNames = ref.watch(
      workbenchControllerProvider.select(
        (state) => <String, String>{
          for (final workspaces in state.workspacesByProject.values)
            for (final workspace in workspaces) workspace.id: workspace.name,
        },
      ),
    );
    final recipients = targets.value ?? const <InboxRecipient>[];
    final sorted = <InboxRecipient>[...recipients]
      ..sort(
        (a, b) => _targetLabel(
          a,
          workspaceNames,
        ).compareTo(_targetLabel(b, workspaceNames)),
      );
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDialogHeader(
            title: 'Ask Agent',
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              spacing: AleraTokens.space12,
              children: <Widget>[
                if (targets.hasError)
                  AleraInlineNotice(
                    tone: .warning,
                    message: inboxErrorMessage(targets.error!),
                  )
                else if (targets.hasValue && recipients.isEmpty)
                  const AleraInlineNotice(
                    message: 'No running agent reports its turns right now. Start an agent in a workspace to ask it.',
                  ),
                AleraDropdownField<String>(
                  key: const ValueKey<String>('inboxComposerTarget'),
                  labelText: 'Agent',
                  hintText: targets.isLoading
                      ? 'Loading agents...'
                      : 'Choose an agent',
                  value: recipients.any((item) => item.handle == _target)
                      ? _target
                      : null,
                  filterable: sorted.length > 6,
                  entries: <AleraDropdownFieldEntry<String>>[
                    for (final recipient in sorted)
                      AleraDropdownFieldEntry<String>(
                        value: recipient.handle,
                        label: _targetLabel(recipient, workspaceNames),
                      ),
                  ],
                  onChanged: (handle) => setState(() => _target = handle),
                ),
                AleraTextField(
                  key: const ValueKey<String>('inboxComposerBody'),
                  controller: _body,
                  labelText: 'Question',
                  hintText: 'What do you want to ask?',
                  minLines: 4,
                  maxLines: 10,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onCommandEnter: () => unawaited(_send()),
                ),
                AleraTextField(
                  controller: _subject,
                  labelText: 'Subject',
                  hintText: 'Defaults to the first line of the question',
                ),
                Row(
                  spacing: AleraTokens.space12,
                  children: <Widget>[
                    Expanded(
                      child: AleraTextField(
                        controller: _inbox,
                        labelText: 'Inbox',
                      ),
                    ),
                    Expanded(
                      child: AleraDropdownField<Duration>(
                        labelText: 'Expires If Not Delivered',
                        value: _expiry,
                        entries: <AleraDropdownFieldEntry<Duration>>[
                          for (final choice in inboxExpiryChoices)
                            AleraDropdownFieldEntry<Duration>(
                              value: choice,
                              label: _expiryLabel(choice),
                            ),
                        ],
                        onChanged: (value) => setState(() => _expiry = value),
                      ),
                    ),
                  ],
                ),
                if (_error != null)
                  AleraInlineNotice(tone: .error, message: _error!),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    key: const ValueKey<String>('inboxComposerSend'),
                    onPressed: _canSend ? () => unawaited(_send()) : null,
                    icon: const Icon(AleraIcons.send, size: AleraTokens.iconMd),
                    label: Text(_sending ? 'Asking...' : 'Ask'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _targetLabel(InboxRecipient recipient, Map<String, String> workspaces) {
  final workspace =
      workspaces[recipient.workspaceId] ?? recipient.workspaceId ?? 'Unknown';
  final title = recipient.tabTitle?.trim();
  final agent = inboxAgentLabel(recipient.agent);
  return title == null || title.isEmpty
      ? '$workspace / $agent'
      : '$workspace / $agent: $title';
}
