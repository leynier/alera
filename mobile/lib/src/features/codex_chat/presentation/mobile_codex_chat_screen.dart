import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileCodexChatScreen extends ConsumerStatefulWidget {
  const MobileCodexChatScreen({
    super.key,
    required this.hostId,
    required this.tabId,
  });

  final String hostId;
  final String tabId;

  @override
  ConsumerState<MobileCodexChatScreen> createState() =>
      _MobileCodexChatScreenState();
}

class _MobileCodexChatScreenState extends ConsumerState<MobileCodexChatScreen> {
  late final TextEditingController _composer;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(
      mobileCodexControllerProvider(widget.hostId, widget.tabId),
    );
    final controller = ref.read(
      mobileCodexControllerProvider(widget.hostId, widget.tabId).notifier,
    );
    return switch (value) {
      AsyncData(value: final state) => _buildChat(state, controller),
      AsyncError(:final error) => Center(child: Text(error.toString())),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildChat(MobileCodexState state, MobileCodexController controller) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: AleraTokens.contentPadding,
            children: <Widget>[
              for (final event in state.events)
                Card(
                  child: Padding(
                    padding: AleraTokens.contentPadding,
                    child: SelectableText(mobileCodexEventText(event)),
                  ),
                ),
              for (final request in state.pendingRequests)
                if (mobileCodexRequestIsApproval(request))
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: AleraTokens.contentPadding,
                      child: Wrap(
                        spacing: AleraTokens.spaceSm,
                        children: <Widget>[
                          const Text('Codex Needs Approval'),
                          FilledButton(
                            onPressed: () =>
                                unawaited(controller.respond(request, true)),
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: () =>
                                unawaited(controller.respond(request, false)),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.spaceMd,
            ),
            child: Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: AleraTokens.contentPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Message Codex'),
                ),
              ),
              IconButton.filled(
                onPressed: state.busy
                    ? () => unawaited(controller.stop())
                    : () {
                        final text = _composer.text;
                        _composer.clear();
                        unawaited(controller.send(text));
                      },
                icon: Icon(state.busy ? Icons.stop : Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
