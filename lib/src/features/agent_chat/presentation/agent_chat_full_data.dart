import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A retained payload can be megabytes of one-line JSON. Only its head is laid
// out; Copy Full Data carries the exact text.
const int _maxPreviewCharacters = 20000;

/// Whether the runtime retained more of [item] than its row carries.
bool agentChatItemHasFullData(AgentChatItem item) =>
    item.normalized['payloadRef'] is Map;

/// The chat whose item details may load retained payloads. Provided once by
/// the chat surface so timeline rows need no extra parameters.
class const AgentChatFullDataScope({
  super.key,
  required final AgentChatRef chat,
  required super.child,
}) extends InheritedWidget {
  static AgentChatRef? maybeChatOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AgentChatFullDataScope>()
      ?.chat;

  @override
  bool updateShouldNotify(AgentChatFullDataScope oldWidget) =>
      chat.chatId != oldWidget.chat.chatId ||
      chat.workspaceId != oldWidget.chat.workspaceId;
}

/// Load Full Data for [item], wired to the runtime. Absent when the item
/// advertises no payload or nothing can serve one.
class const AgentChatItemFullData({
  super.key,
  required final AgentChatItem item,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = AgentChatFullDataScope.maybeChatOf(context);
    final Object repository = ref.watch(agentChatRepositoryProvider);
    if (chat == null ||
        repository is! AgentChatPayloadRepository ||
        !agentChatItemHasFullData(item)) {
      return const SizedBox.shrink();
    }
    return AgentChatFullDataPanel(
      // A new item version may carry different data, so it starts over.
      key: ValueKey<String>(
        '${chat.workspaceId}/${chat.chatId}/${item.id}/'
        '${item.updatedAt.microsecondsSinceEpoch}/${item.status.name}/'
        '${item.normalized['payloadRef']}',
      ),
      load: () => repository.loadPayloadJson(chat, itemId: item.id),
    );
  }
}

/// An explicit, retryable load of one exact payload, previewed in bounded
/// form. Nothing is fetched until the person asks.
class const AgentChatFullDataPanel({
  super.key,
  required final Future<String> Function() load,
}) extends StatefulWidget {
  @override
  State<AgentChatFullDataPanel> createState() => _AgentChatFullDataPanelState();
}

class _AgentChatFullDataPanelState extends State<AgentChatFullDataPanel> {
  bool _loading = false;
  String? _text;
  Object? _error;
  int _attempt = 0;

  Future<void> _load() async {
    final attempt = ++_attempt;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await widget.load();
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _loading = false;
        _text = text;
      });
    } on Object catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AleraToast.publish(message: 'Full data copied.');
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text != null) {
      return _LoadedFullData(text: text, onCopy: () => unawaited(_copy(text)));
    }
    final theme = Theme.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AleraTokens.space4,
      children: <Widget>[
        if (error != null)
          Text(
            agentChatFullDataErrorMessage(error),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        TextButton.icon(
          onPressed: _loading ? null : () => unawaited(_load()),
          icon: _loading
              ? const SizedBox.square(
                  dimension: AleraTokens.iconSm,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                )
              : null,
          label: Text(error == null ? 'Load Full Data' : 'Retry'),
        ),
      ],
    );
  }
}

class const _LoadedFullData({
  required final String text,
  required final VoidCallback onCopy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preview = agentChatFullDataPreview(text, _maxPreviewCharacters);
    final label = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AleraTokens.space4,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                agentChatFullDataCaption(preview.length, text.length),
                style: label,
              ),
            ),
            TextButton(onPressed: onCopy, child: const Text('Copy Full Data')),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AleraTokens.bg,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: AleraTokens.agentChatDetailsMaxHeight,
            ),
            // Wrapped rather than scrolled sideways: retained JSON is usually
            // one long line.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AleraTokens.space8),
              child: SelectableText(
                preview,
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The head of [text], never ending inside a surrogate pair.
@visibleForTesting
String agentChatFullDataPreview(String text, int maxCharacters) {
  if (text.length <= maxCharacters) return text;
  var end = maxCharacters;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return text.substring(0, end);
}

@visibleForTesting
String agentChatFullDataCaption(int shown, int total) => shown >= total
    ? '${_grouped(total)} characters'
    : 'First ${_grouped(shown)} of ${_grouped(total)} characters';

@visibleForTesting
String agentChatFullDataErrorMessage(Object error) => switch (error) {
  AgentChatUpdateRequired() ||
  AgentChatConnectionException() ||
  AgentChatRequestException() => agentChatErrorMessage(error),
  FormatException() => 'The runtime returned incomplete data.',
  _ => 'Could not load the full data.',
};

String _grouped(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) out.write(',');
    out.write(digits[index]);
  }
  return out.toString();
}
