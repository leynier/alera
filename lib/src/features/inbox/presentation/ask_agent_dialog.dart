import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/question_delivery_choice.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showAskAgentDialog(BuildContext context, {String? targetHandle}) =>
    showDialog<void>(
      context: context,
      builder: (_) => AskAgentDialog(initialTarget: targetHandle),
    );

/// Asks a running agent a new question, by default from the shared `ext:user`
/// inbox.
class AskAgentDialog extends ConsumerStatefulWidget {
  const AskAgentDialog({super.key, this.initialTarget});

  final String? initialTarget;

  @override
  ConsumerState<AskAgentDialog> createState() => _AskAgentDialogState();
}

class _AskAgentDialogState extends ConsumerState<AskAgentDialog> {
  final _inbox = TextEditingController(text: inboxUserAddress);
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _target;
  InboxDelivery _delivery = InboxDelivery.now;
  Duration _expiry = questionDefaultExpiry;
  bool _advanced = false;
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

  Future<void> _send(InboxRecipient? recipient, bool deliverySupported) async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(inboxRepositoryProvider)
          .ask(
            InboxAskRequest(
              body: _body.text.trim(),
              inbox: _inbox.text.trim().isEmpty ? null : _inbox.text.trim(),
              to: _target,
              subject: _subject.text,
              expiresIn: _expiry == questionDefaultExpiry ? null : _expiry,
              delivery: deliverySupported
                  ? effectiveQuestionDelivery(
                      _delivery,
                      recipient?.deliveryMode,
                    )
                  : null,
            ),
          );
      if (!mounted) return;
      final navigation = ref.read(activityNavigationProvider.notifier);
      navigation.filterInbox(null);
      navigation.selectThread(result.threadId.isEmpty ? null : result.threadId);
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
    final deliverySupported =
        ref.watch(inboxDeliverySupportedProvider).value ?? false;
    final places = ref.watch(
      workbenchControllerProvider.select(
        (state) => <String, String>{
          for (final project in state.projects)
            for (final workspace
                in state.workspacesByProject[project.id] ?? const [])
              workspace.id: '${project.name} / ${workspace.name}',
        },
      ),
    );
    final recipients = targets.value ?? const <InboxRecipient>[];
    String placeOf(InboxRecipient recipient) =>
        places[recipient.workspaceId] ?? recipient.workspaceId ?? 'Unknown';
    final sorted = <InboxRecipient>[...recipients]
      ..sort((a, b) {
        final place = placeOf(a).compareTo(placeOf(b));
        return place != 0 ? place : _targetLabel(a).compareTo(_targetLabel(b));
      });
    final recipient = recipients
        .where((item) => item.handle == _target)
        .firstOrNull;
    void send() => unawaited(_send(recipient, deliverySupported));
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
          Flexible(
            child: SingleChildScrollView(
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
                    value: recipient?.handle,
                    filterable: sorted.length > 6,
                    filterHintText: 'Search Agents',
                    entries: <AleraDropdownFieldEntry<String>>[
                      for (final item in sorted)
                        AleraDropdownFieldEntry<String>(
                          value: item.handle,
                          label: _targetLabel(item),
                          group: placeOf(item),
                          detail: questionTargetDeliveryLabel(
                            item.deliveryMode,
                          ),
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
                    onCommandEnter: send,
                  ),
                  AleraTextField(
                    controller: _subject,
                    labelText: 'Subject',
                    hintText: 'Defaults to the first line of the question',
                  ),
                  if (deliverySupported)
                    QuestionDeliveryChoice(
                      key: const ValueKey<String>('inboxComposerDelivery'),
                      selected: _delivery,
                      targetMode: recipient?.deliveryMode,
                      expiry: _expiry,
                      onChanged: (value) => setState(() => _delivery = value),
                    )
                  else
                    Text(
                      questionLegacyDeliveryCaption,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.foregroundMuted),
                    ),
                  _AdvancedFields(
                    expanded: _advanced,
                    onToggle: () => setState(() => _advanced = !_advanced),
                    inbox: _inbox,
                    expiry: _expiry,
                    onExpiryChanged: (value) => setState(() => _expiry = value),
                  ),
                  if (_error != null)
                    AleraInlineNotice(tone: .error, message: _error!),
                  Row(
                    mainAxisAlignment: .end,
                    spacing: AleraTokens.space8,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey<String>('inboxComposerSend'),
                        onPressed: _canSend ? send : null,
                        icon: const Icon(
                          AleraIcons.send,
                          size: AleraTokens.iconMd,
                        ),
                        label: Text(_sending ? 'Asking...' : 'Ask'),
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

/// Inbox and expiry, folded away because almost every question uses the
/// defaults.
class const _AdvancedFields({
  required final bool expanded,
  required final VoidCallback onToggle,
  required final TextEditingController inbox,
  required final Duration expiry,
  required final ValueChanged<Duration> onExpiryChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    spacing: AleraTokens.space8,
    children: <Widget>[
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey<String>('inboxComposerAdvanced'),
          onPressed: onToggle,
          icon: Icon(
            expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
            size: AleraTokens.iconMd,
          ),
          label: const Text('Advanced'),
        ),
      ),
      if (expanded)
        Row(
          spacing: AleraTokens.space12,
          children: <Widget>[
            Expanded(
              child: AleraTextField(
                key: const ValueKey<String>('inboxComposerInbox'),
                controller: inbox,
                labelText: 'Inbox',
              ),
            ),
            Expanded(
              child: AleraDropdownField<Duration>(
                key: const ValueKey<String>('inboxComposerExpiry'),
                labelText: 'Expires If Not Delivered',
                value: expiry,
                entries: <AleraDropdownFieldEntry<Duration>>[
                  for (final choice in questionExpiryChoices)
                    AleraDropdownFieldEntry<Duration>(
                      value: choice,
                      label: questionExpiryLabel(choice),
                    ),
                ],
                onChanged: onExpiryChanged,
              ),
            ),
          ],
        ),
    ],
  );
}

String _targetLabel(InboxRecipient recipient) {
  final title = recipient.tabTitle?.trim();
  final agent = inboxAgentLabel(recipient.agent);
  final name = title == null || title.isEmpty ? agent : '$agent: $title';
  return recipient.deliveryMode == InboxDeliveryMode.check
      ? '$name (coordinator)'
      : name;
}
