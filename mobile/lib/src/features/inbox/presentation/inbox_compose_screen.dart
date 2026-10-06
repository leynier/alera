import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks a running agent a question from the shared `ext:user` inbox. Pops the
/// new thread id once the runtime accepted the question.
class const InboxComposeScreen({
  super.key,
  required final String hostId,
  final String? workspaceId,
  final String? preselectedHandle,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<InboxComposeScreen> createState() => _InboxComposeScreenState();
}

class _InboxComposeScreenState extends ConsumerState<InboxComposeScreen> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _body = TextEditingController();
  late String? _selected = widget.preselectedHandle;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final available =
        ref
            .read(
              mobileInboxTargetsProvider(
                widget.hostId,
                workspaceId: widget.workspaceId,
              ),
            )
            .value ??
        const <InboxRecipient>[];
    final to = available.any((target) => target.handle == _selected)
        ? _selected
        : null;
    final body = _body.text.trim();
    if (to == null || body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(widget.hostId).future,
      );
      final result = await repository.ask(
        to: to,
        body: body,
        subject: _subject.text,
      );
      if (mounted) Navigator.of(context).pop(result.threadId);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(
      mobileInboxTargetsProvider(
        widget.hostId,
        workspaceId: widget.workspaceId,
      ),
    );
    final names =
        ref.watch(mobileInboxWorkspaceNamesProvider(widget.hostId)).value ??
        const <String, String>{};
    // A preselected terminal only counts once the runtime lists it as an agent.
    final available = targets.value ?? const <InboxRecipient>[];
    final selected = available.any((target) => target.handle == _selected)
        ? _selected
        : null;
    final canSend =
        !_sending && selected != null && _body.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask Agent'),
        actions: <Widget>[
          TextButton(
            onPressed: canSend ? () => unawaited(_send()) : null,
            child: const Text('Send'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            const AleraSectionHeader(label: 'Agent'),
            switch (targets) {
              AsyncValue(value: null, hasError: true, :final error) =>
                AleraEmptyState(
                  message: 'The host could not list its agents.',
                  detail: '$error',
                ),
              AsyncValue(value: null) => const Center(
                child: CircularProgressIndicator(),
              ),
              AsyncValue(value: final items?) when items.isEmpty =>
                const AleraEmptyState(
                  icon: AleraIcons.inbox,
                  message: 'No agent is running here. Start one, then ask it a question.',
                ),
              AsyncValue(value: final items?) => _TargetPicker(
                targets: items,
                workspaceNames: names,
                selected: selected,
                onSelected: (handle) => setState(() => _selected = handle),
              ),
            },
            const SizedBox(height: AleraTokens.spaceMd),
            const AleraSectionHeader(label: 'Question'),
            AleraTextField(
              controller: _subject,
              labelText: 'Subject',
              hintText: 'Defaults to the first line of the question',
            ),
            const SizedBox(height: AleraTokens.space8),
            AleraTextField(
              controller: _body,
              labelText: 'Question',
              minLines: 4,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'The agent receives the question when it finishes its turn. If that does not happen within 5 hours, the question expires.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class const _TargetPicker({
  required final List<InboxRecipient> targets,
  required final Map<String, String> workspaceNames,
  required final String? selected,
  required final ValueChanged<String> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<InboxRecipient>>{};
    for (final target in targets) {
      groups.putIfAbsent(target.workspaceId ?? '', () => []).add(target);
    }
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          for (final MapEntry(key: workspaceId, value: items)
              in groups.entries) ...<Widget>[
            if (groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: Text(
                  workspaceNames[workspaceId] ?? workspaceId,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            for (final target in items)
              RadioListTile<String>(
                value: target.handle,
                title: Text(target.label),
                subtitle: Text(inboxDeliveryHint(target.deliveryMode)),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ],
      ),
    );
  }
}
