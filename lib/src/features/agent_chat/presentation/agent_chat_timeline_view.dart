import 'dart:collection';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_entry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The scrolling conversation. It follows new output while the reader is at
/// the bottom, keeps the reader's place when earlier history is loaded above,
/// and reuses the widgets of rows whose data did not change.
class const AgentChatTimelineView({
  super.key,
  required final AgentChatTimelineProjection projection,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final Set<String> respondingRequestIds,
  required final bool enabled,
  required final String workspacePath,
  required final bool canLoadEarlier,
  required final bool loadingEarlier,
  required final VoidCallback onLoadEarlier,
}) extends StatefulWidget {
  @override
  State<AgentChatTimelineView> createState() => _AgentChatTimelineViewState();
}

final class _CachedEntry {
  _CachedEntry(this.token, this.widget, this.anchorKey);

  final Object token;
  final Widget widget;
  final GlobalKey anchorKey;
}

class _AgentChatTimelineViewState extends State<AgentChatTimelineView> {
  static const int _cacheLimit = 128;
  static const String _entryKeyPrefix = 'agent-chat-entry:';

  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final LinkedHashMap<String, _CachedEntry> _cache =
      LinkedHashMap<String, _CachedEntry>();
  bool _showJumpToBottom = false;
  bool _followScheduled = false;
  ({String key, double top})? _anchor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_handleScroll);
    _followOutput();
  }

  @override
  void didUpdateWidget(covariant AgentChatTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath ||
        !identical(oldWidget.actions, widget.actions) ||
        oldWidget.enabled != widget.enabled) {
      _cache.clear();
    }
    if (!oldWidget.loadingEarlier && widget.loadingEarlier) {
      _anchor = _captureAnchor();
    }
    if (oldWidget.loadingEarlier && !widget.loadingEarlier) {
      final anchor = _anchor;
      _anchor = null;
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreAnchor(anchor),
        );
      }
    } else if (!identical(oldWidget.projection, widget.projection) &&
        !_showJumpToBottom) {
      _followOutput();
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scroll.hasClients) return;
    final show = _scroll.position.extentAfter > AleraTokens.space48;
    if (show != _showJumpToBottom) setState(() => _showJumpToBottom = show);
  }

  /// Lazily built rows change the scroll extent as they lay out, so one jump
  /// can land short; settle over a few frames.
  void _followOutput({bool animate = false}) {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var attempt = 0; attempt < 4; attempt += 1) {
          if (!mounted || !_scroll.hasClients) return;
          final position = _scroll.position;
          if (position.extentAfter < AleraTokens.dividerExtent) return;
          if (animate && attempt == 0) {
            await _scroll.animateTo(
              position.maxScrollExtent,
              duration: AleraTokens.durationMid,
              curve: Curves.easeOut,
            );
          } else {
            _scroll.jumpTo(position.maxScrollExtent);
          }
          await WidgetsBinding.instance.endOfFrame;
        }
      } finally {
        _followScheduled = false;
      }
    });
  }

  ({String key, double top})? _captureAnchor() {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    ({String key, double top})? best;
    for (final entry in _cache.entries) {
      final box =
          entry.value.anchorKey.currentContext?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top >= viewportBottom || top + box.size.height <= viewportTop) {
        continue;
      }
      if (best == null || top < best.top) best = (key: entry.key, top: top);
    }
    return best;
  }

  void _restoreAnchor(({String key, double top}) anchor) {
    if (!mounted || !_scroll.hasClients) return;
    final box =
        _cache[anchor.key]?.anchorKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final correction = box.localToGlobal(Offset.zero).dy - anchor.top;
    if (correction.abs() < 0.5) return;
    final position = _scroll.position;
    _scroll.jumpTo(
      (position.pixels + correction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Object _tokenFor(AgentChatTimelineEntry entry) => switch (entry) {
    AgentChatTurnEntry(:final section) => section,
    AgentChatStandaloneEntry(:final item) => item,
    AgentChatOutgoingEntry(:final message) => message,
    AgentChatRequestEntry(:final request) => (
      request,
      widget.respondingRequestIds.contains(request.id),
    ),
  };

  Widget _buildEntry(BuildContext context, int index) {
    final entry = widget.projection.entries[index];
    final token = _tokenFor(entry);
    final cached = _cache.remove(entry.key);
    if (cached != null && cached.token == token) {
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
              expansion: widget.expansion,
              responding: switch (entry) {
                AgentChatRequestEntry(:final request) =>
                  widget.respondingRequestIds.contains(request.id),
                _ => false,
              },
              enabled: widget.enabled,
              workspacePath: widget.workspacePath,
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
      key: _viewportKey,
      children: <Widget>[
        AleraShimmerScope(
          child: SelectionArea(
            child: CustomScrollView(
              key: const ValueKey<String>('agent-chat-timeline'),
              controller: _scroll,
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: AleraTokens.space48,
                    child: widget.canLoadEarlier || widget.loadingEarlier
                        ? Center(
                            child: widget.loadingEarlier
                                ? AleraShimmerText(
                                    text: 'Loading earlier messages',
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                                    label: const Text('Load Earlier Messages'),
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
                const SliverToBoxAdapter(
                  child: SizedBox(height: AleraTokens.space24),
                ),
              ],
            ),
          ),
        ),
        if (_showJumpToBottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: AleraTokens.space12,
            child: Center(
              child: IconButton(
                key: const ValueKey<String>('agent-chat-scroll-to-bottom'),
                tooltip: 'Scroll To Bottom',
                onPressed: () => _followOutput(animate: true),
                style: IconButton.styleFrom(
                  backgroundColor: AleraTokens.surfaceElevated,
                  foregroundColor: AleraTokens.foreground,
                  side: const BorderSide(color: AleraTokens.border),
                  shape: const CircleBorder(),
                ),
                icon: const Icon(
                  AleraIcons.arrowDown,
                  size: AleraTokens.iconLg,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
