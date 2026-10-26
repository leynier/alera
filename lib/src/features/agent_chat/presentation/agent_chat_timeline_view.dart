import 'dart:async';
import 'dart:collection';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_announcer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_entry.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_scrolling.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The scrolling conversation. It follows new output while the reader is at
/// the end, pins a just-sent prompt near the top until the agent starts using
/// tools, stays put once the reader scrolls away, keeps the reader's place
/// when earlier history loads above, and restores scroll and folds when the
/// tab comes back. Rows whose data did not change reuse their widgets, so a
/// stream into the live turn rebuilds only that turn.
class const AgentChatTimelineView({
  super.key,
  required final AgentChatTimelineProjection projection,
  required final AgentChatTimelineActions actions,
  required final String workspacePath,
  required final bool canLoadEarlier,
  required final bool loadingEarlier,
  required final VoidCallback onLoadEarlier,

  /// Client message ids whose attachments are still uploading.
  final Set<String> preparingAttachmentIds = const <String>{},
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTimelineView> createState() =>
      _AgentChatTimelineViewState();
}

/// A stand-in token for an outgoing message while its attachments upload.
/// The message object does not change when the upload starts, so without it
/// the cached row would keep saying Sending.
final Expando<Object> _uploadingTokens = Expando<Object>('uploading');

final class _CachedEntry {
  _CachedEntry(this.token, this.widget, this.anchorKey);

  final Object token;
  final Widget widget;
  final GlobalKey anchorKey;
}

class _AgentChatTimelineViewState extends ConsumerState<AgentChatTimelineView>
    with AgentChatTimelineScrolling<AgentChatTimelineView>
    implements AgentChatFindViewport {
  static const int _cacheLimit = 128;
  static const String _entryKeyPrefix = 'agent-chat-entry:';

  final LinkedHashMap<String, _CachedEntry> _cache =
      LinkedHashMap<String, _CachedEntry>();
  late AgentChatTimelineSession _session;
  ({String key, double top})? _historyAnchor;
  AgentChatFindController? _find;

  @override
  AgentChatTimelineSession get session => _session;

  @override
  RenderBox? entryBox(String key) {
    final box =
        _cache[key]?.anchorKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.attached || !box.hasSize ? null : box;
  }

  @override
  Iterable<String> get builtEntryKeys => _cache.keys;

  @override
  int? indexOfEntry(String key) => widget.projection.indexOfKey(key);

  @override
  int? get firstVisibleEntryIndex {
    final key = captureAnchor()?.key;
    return key == null ? null : indexOfEntry(key);
  }

  /// Opens the folds that hide the match, then scrolls its row into view.
  @override
  void reveal(AgentChatFindMatch match) {
    final index = indexOfEntry(match.entryKey);
    if (index == null) return;
    final expansion = _session.expansion;
    final closed = <String>[
      for (final key in match.foldKeys)
        if (!expansion.isExpanded(key, byDefault: false)) key,
    ];
    if (closed.isNotEmpty) {
      for (final key in closed) {
        expansion.set(key, expanded: true);
      }
      final cached = _cache[match.entryKey];
      if (cached != null) {
        // A fresh token rebuilds the entry with its folds open while the
        // anchor key, and so the row's state, survives.
        _cache[match.entryKey] = _CachedEntry(
          Object(),
          cached.widget,
          cached.anchorKey,
        );
      }
      setState(() {});
    }
    revealEntry(
      match.entryKey,
      index: index,
      count: widget.projection.entries.length,
      onBuilt: () {
        final target =
            _find?.targetContext(match.targetKey) ??
            _cache[match.entryKey]?.anchorKey.currentContext;
        if (target == null) return;
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0.2,
            duration: AleraTokens.durationMid,
            curve: Curves.easeOut,
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _session = ref
        .read(agentChatTimelineSessionsProvider)
        .of(widget.actions.chatId);
    initScrolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final find = AgentChatFindScope.maybeOf(context);
    if (identical(find, _find)) return;
    _find?.detach(this);
    _find = find?..attach(this);
  }

  @override
  void didUpdateWidget(covariant AgentChatTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions.chatId != widget.actions.chatId) {
      saveScrolling();
      _session = ref
          .read(agentChatTimelineSessionsProvider)
          .of(widget.actions.chatId);
      _cache.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => restoreScrolling());
      return;
    }
    if (oldWidget.workspacePath != widget.workspacePath ||
        !identical(oldWidget.actions, widget.actions)) {
      _cache.clear();
    }
    if (!oldWidget.loadingEarlier && widget.loadingEarlier) {
      _historyAnchor = captureAnchor();
    }
    if (oldWidget.loadingEarlier && !widget.loadingEarlier) {
      final anchor = _historyAnchor;
      _historyAnchor = null;
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restoreAnchor(anchor),
        );
      }
      return;
    }
    if (identical(oldWidget.projection, widget.projection)) return;
    if (TickerMode.valuesOf(context).enabled) {
      AgentChatTimelineAnnouncer.announce(
        context,
        before: oldWidget.projection,
        after: widget.projection,
      );
    }
    _trackSend(oldWidget.projection);
    applyScrollMode();
  }

  /// A message this client just sent anchors the timeline; once the runtime
  /// stamps it into a turn, the anchor moves to that turn, and once the turn
  /// starts using tools the timeline follows the output instead.
  void _trackSend(AgentChatTimelineProjection before) {
    final projection = widget.projection;
    for (final entry in projection.entries.reversed) {
      if (entry is! AgentChatOutgoingEntry) continue;
      if (before.indexOfKey(entry.key) != null) break;
      if (entry.message.status == AgentChatOutgoingStatus.failed) break;
      startAnchoring(entry.key, clientMessageId: entry.message.clientMessageId);
      return;
    }
    if (session.mode != AgentChatScrollMode.anchoring) return;
    var key = session.anchoredEntryKey;
    if (key != null && projection.indexOfKey(key) == null) {
      key = _turnKeyFor(session.anchoredClientMessageId);
      session.anchoredEntryKey = key;
    }
    final index = key == null ? null : projection.indexOfKey(key);
    final entry = index == null ? null : projection.entries[index];
    if (entry == null) {
      stopAnchoring();
    } else if (entry case AgentChatTurnEntry(:final section)
        when section.activity.any((row) => row is AgentChatActionGroupRow)) {
      stopAnchoring();
    }
  }

  String? _turnKeyFor(String? clientMessageId) {
    if (clientMessageId == null) return null;
    for (final entry in widget.projection.entries.reversed) {
      if (entry is AgentChatTurnEntry &&
          entry.section.prompts.any(
            (prompt) => prompt.clientMessageId == clientMessageId,
          )) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  void deactivate() {
    saveScrolling();
    super.deactivate();
  }

  @override
  void dispose() {
    _find?.detach(this);
    disposeScrolling();
    super.dispose();
  }

  Object _tokenFor(AgentChatTimelineEntry entry) => switch (entry) {
    AgentChatTurnEntry(:final section) => section,
    AgentChatStandaloneEntry(:final item) => item,
    AgentChatTransferEntry(:final transfer) => transfer,
    AgentChatOutgoingEntry(:final message)
        when widget.preparingAttachmentIds.contains(message.clientMessageId) =>
      _uploadingTokens[message] ??= Object(),
    AgentChatOutgoingEntry(:final message) => message,
  };

  Widget _buildEntry(BuildContext context, int index) {
    final entry = widget.projection.entries[index];
    final token = _tokenFor(entry);
    final cached = _cache.remove(entry.key);
    if (cached != null && identical(cached.token, token)) {
      _cache[entry.key] = cached;
      return cached.widget;
    }
    final anchorKey = cached?.anchorKey ?? GlobalKey();
    final child = Center(
      key: ValueKey<String>('$_entryKeyPrefix${entry.key}'),
      child: ConstrainedBox(
        key: anchorKey,
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.agentChatConversationMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space16),
          child: SizedBox(
            width: double.infinity,
            child: AgentChatTimelineEntryView(
              entry: entry,
              actions: widget.actions,
              expansion: _session.expansion,
              workspacePath: widget.workspacePath,
              preparingAttachmentIds: widget.preparingAttachmentIds,
            ),
          ),
        ),
      ),
    );
    _cache[entry.key] = _CachedEntry(token, child, anchorKey);
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return child;
  }

  int? _findIndex(Key key) {
    if (key is! ValueKey<String> || !key.value.startsWith(_entryKeyPrefix)) {
      return null;
    }
    return widget.projection.indexOfKey(
      key.value.substring(_entryKeyPrefix.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      key: viewportKey,
      children: <Widget>[
        AleraShimmerScope(
          child: SelectionArea(
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                recordReaderPlace();
                return false;
              },
              child: CustomScrollView(
                key: const ValueKey<String>('agent-chat-timeline'),
                controller: scroll,
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: AleraTokens.space48,
                      child: widget.canLoadEarlier || widget.loadingEarlier
                          ? Center(
                              child: widget.loadingEarlier
                                  ? AleraShimmerText(
                                      text: 'Loading earlier messages',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AleraTokens.foregroundMuted,
                                          ),
                                    )
                                  : TextButton.icon(
                                      key: const ValueKey<String>(
                                        'agent-chat-load-earlier',
                                      ),
                                      onPressed: widget.onLoadEarlier,
                                      icon: const Icon(
                                        AleraIcons.chevronUp,
                                        size: AleraTokens.iconSm,
                                      ),
                                      label: const Text(
                                        'Load Earlier Messages',
                                      ),
                                    ),
                            )
                          : null,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: widget.projection.entries.length,
                    itemBuilder: _buildEntry,
                    findChildIndexCallback: _findIndex,
                  ),
                  SliverToBoxAdapter(
                    child: ValueListenableBuilder<double>(
                      valueListenable: anchorSpacer,
                      builder: (context, spacer, _) =>
                          SizedBox(height: AleraTokens.space24 + spacer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AleraTokens.space12,
          child: ValueListenableBuilder<bool>(
            valueListenable: showScrollToEnd,
            builder: (context, show, _) => show
                ? Center(
                    child: _ScrollToEndPill(
                      label: agentChatScrollToEndLabel(
                        widget.projection.requests,
                      ),
                      onPressed: () => followToEnd(animate: true),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class const _ScrollToEndPill({
  required final String label,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final attention = label != agentChatScrollToEndDefaultLabel;
    return OutlinedButton.icon(
      key: const ValueKey<String>('agent-chat-scroll-to-bottom'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AleraTokens.surfaceElevated,
        foregroundColor: attention
            ? AleraTokens.warning
            : AleraTokens.foreground,
        side: BorderSide(
          color: attention ? AleraTokens.warning : AleraTokens.border,
        ),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(AleraIcons.arrowDown, size: AleraTokens.iconMd),
      label: Text(label),
    );
  }
}
