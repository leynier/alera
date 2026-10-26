import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_find_requests.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "3 of 12", or that nothing matched; null before anything is typed.
String? agentChatFindCountLabel(AgentChatFindController find) {
  if (find.query.trim().isEmpty) return null;
  if (find.matchCount == 0) return 'No results';
  return '${find.activeIndex + 1} of ${find.matchCount}';
}

/// Hosts find over a chat's timeline: opens on Find in Chat for this chat,
/// floats the bar in the timeline's top corner, and hands the focus back to
/// where it was when the bar closes.
class const AgentChatFindHost({
  super.key,
  required final AgentChatRef chat,
  required final Widget child,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatFindHost> createState() => _AgentChatFindHostState();
}

class _AgentChatFindHostState extends ConsumerState<AgentChatFindHost> {
  final AgentChatFindController _find = AgentChatFindController();
  FocusNode? _returnFocus;

  AgentChatControllerProvider get _provider =>
      agentChatControllerProvider(widget.chat.chatId, widget.chat.workspaceId);

  @override
  void initState() {
    super.initState();
    ref
      ..listenManual(agentChatFindRequestsProvider, (_, request) {
        if (request?.chatId == widget.chat.chatId) _open();
      })
      ..listenManual(_provider.select((state) => state.projection), (
        _,
        projection,
      ) {
        if (projection != null) _find.updateProjection(projection);
      }, fireImmediately: true);
  }

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  void _open() {
    if (!mounted) return;
    if (!_find.isOpen) _returnFocus = FocusManager.instance.primaryFocus;
    _find.open();
  }

  void _close() {
    _find.close();
    final previous = _returnFocus;
    _returnFocus = null;
    if (previous != null && (previous.context?.mounted ?? false)) {
      previous.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final olderHistory = ref.watch(
      _provider.select((state) => state.thread?.historyBefore != null),
    );
    return AgentChatFindScope(
      controller: _find,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          Positioned(
            top: AleraTokens.space8,
            left: AleraTokens.space12,
            right: AleraTokens.space12,
            child: ListenableBuilder(
              listenable: _find,
              builder: (context, _) => _find.isOpen
                  ? Align(
                      alignment: Alignment.topRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AleraTokens.agentChatFindBarWidth,
                        ),
                        child: AgentChatFindBar(
                          controller: _find,
                          olderHistory: olderHistory,
                          onClose: _close,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The find field with its count, Previous and Next, and Close. Enter moves
/// to the next match, Shift+Enter to the previous one, and Escape closes.
/// [olderHistory] says that earlier messages are not loaded, and so not
/// searched.
class const AgentChatFindBar({
  super.key,
  required final AgentChatFindController controller,
  required final bool olderHistory,
  required final VoidCallback onClose,
}) extends StatefulWidget {
  @override
  State<AgentChatFindBar> createState() => _AgentChatFindBarState();
}

class _AgentChatFindBarState extends State<AgentChatFindBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.query,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'AgentChatFind');
  int _focusRequests = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _takeFocusRequest();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    _takeFocusRequest();
    setState(() {});
  }

  void _takeFocusRequest() {
    final requests = widget.controller.focusRequests;
    if (requests != _focusRequests) {
      _focusRequests = requests;
      // Pressing the chord again, even while the bar is open, puts the caret
      // back in the field with the query selected, ready to replace.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _text.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _text.text.length,
        );
      });
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.controller.previous();
      } else {
        widget.controller.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final find = widget.controller;
    final count = agentChatFindCountLabel(find);
    final canStep = find.matchCount > 0;
    return DecoratedBox(
      key: const ValueKey<String>('agent-chat-find-bar'),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: AleraTokens.space8,
            offset: Offset(0, AleraTokens.space4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Focus(
              onKeyEvent: _handleKey,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AleraTextField(
                      key: const ValueKey<String>('agent-chat-find-field'),
                      controller: _text,
                      focusNode: _focus,
                      hintText: 'Find in Chat',
                      prefixIcon: AleraIcons.search,
                      dense: true,
                      fillColor: AleraTokens.surfaceVariant,
                      onChanged: find.setQuery,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        count,
                        key: const ValueKey<String>('agent-chat-find-count'),
                        style: AleraTokens.monoStyle.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AleraTokens.space4),
                  AleraIconButton(
                    tooltip: 'Previous Match',
                    icon: AleraIcons.chevronUp,
                    onPressed: canStep ? find.previous : null,
                    minSize: AleraTokens.space32,
                  ),
                  AleraIconButton(
                    tooltip: 'Next Match',
                    icon: AleraIcons.chevronDown,
                    onPressed: canStep ? find.next : null,
                    minSize: AleraTokens.space32,
                  ),
                  AleraIconButton(
                    tooltip: 'Close Find',
                    icon: AleraIcons.close,
                    onPressed: widget.onClose,
                    minSize: AleraTokens.space32,
                  ),
                ],
              ),
            ),
            if (widget.olderHistory)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.space4,
                  AleraTokens.space4,
                  AleraTokens.space4,
                  AleraTokens.space2,
                ),
                child: Text(
                  'Only loaded messages are searched.',
                  key: const ValueKey<String>('agent-chat-find-loaded-only'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
