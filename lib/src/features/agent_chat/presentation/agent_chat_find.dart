import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// What the timeline lends find: bringing a match into view, and the entry
/// the reader is looking at, so a new search starts where they are.
abstract interface class AgentChatFindViewport {
  void reveal(AgentChatFindMatch match);

  int? get firstVisibleEntryIndex;
}

/// Find in one chat's loaded timeline: the query, its matching rows and the
/// active one. Matching runs on the UI isolate because it only reads what is
/// already loaded and caches each item's lowercased text, so a keystroke or a
/// streamed delta re-reads one item at most.
final class AgentChatFindController extends ChangeNotifier {
  bool _open = false;
  String _query = '';
  List<AgentChatFindMatch> _matches = const <AgentChatFindMatch>[];
  int _active = -1;
  int _focusRequests = 0;
  AgentChatTimelineProjection? _projection;
  AgentChatFindViewport? _viewport;
  final Map<String, BuildContext> _targets = <String, BuildContext>{};

  /// The row to highlight; only the rows themselves listen to it, so moving
  /// between matches never rebuilds the timeline.
  final ValueNotifier<String?> activeTarget = ValueNotifier<String?>(null);

  bool get isOpen => _open;
  String get query => _query;
  int get matchCount => _matches.length;

  /// Zero-based; -1 while nothing matches.
  int get activeIndex => _active;

  /// Bumped on every open, so the field refocuses even when already open.
  int get focusRequests => _focusRequests;

  void open() {
    final wasOpen = _open;
    _open = true;
    _focusRequests += 1;
    if (!wasOpen && _query.trim().isNotEmpty) {
      _search(keepActive: false);
    } else {
      notifyListeners();
    }
  }

  void close() {
    _open = false;
    activeTarget.value = null;
    notifyListeners();
  }

  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _search(keepActive: false);
  }

  void next() => _step(1);

  void previous() => _step(-1);

  /// The timeline changed: recount, keeping the active row in place rather
  /// than moving the reader.
  void updateProjection(AgentChatTimelineProjection projection) {
    if (identical(projection, _projection)) return;
    _projection = projection;
    if (_open && _query.trim().isNotEmpty) _search(keepActive: true);
  }

  void attach(AgentChatFindViewport viewport) => _viewport = viewport;

  void detach(AgentChatFindViewport viewport) {
    if (identical(_viewport, viewport)) _viewport = null;
  }

  /// The mounted row [targetKey], if it is built.
  BuildContext? targetContext(String targetKey) {
    final context = _targets[targetKey];
    return context != null && context.mounted ? context : null;
  }

  void registerTarget(String targetKey, BuildContext context) =>
      _targets[targetKey] = context;

  void unregisterTarget(String targetKey, BuildContext context) {
    if (identical(_targets[targetKey], context)) _targets.remove(targetKey);
  }

  void _search({required bool keepActive}) {
    final projection = _projection;
    final previous = _active >= 0 && _active < _matches.length
        ? _matches[_active].targetKey
        : null;
    _matches = projection == null
        ? const <AgentChatFindMatch>[]
        : agentChatFindMatches(projection, _query);
    if (_matches.isEmpty) {
      _active = -1;
    } else if (keepActive && previous != null) {
      final kept = _matches.indexWhere((match) => match.targetKey == previous);
      _active = kept >= 0 ? kept : _active.clamp(0, _matches.length - 1);
    } else {
      _active = _startIndex(projection!);
    }
    _publish(reveal: !keepActive);
  }

  /// The first match at or below the reader's place, else the last one.
  int _startIndex(AgentChatTimelineProjection projection) {
    final top = _viewport?.firstVisibleEntryIndex;
    if (top == null) return _matches.length - 1;
    final index = _matches.indexWhere(
      (match) => (projection.indexOfKey(match.entryKey) ?? -1) >= top,
    );
    return index >= 0 ? index : _matches.length - 1;
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final total = _matches.length;
    _active = ((_active + delta) % total + total) % total;
    _publish(reveal: true);
  }

  void _publish({required bool reveal}) {
    final match = _active >= 0 ? _matches[_active] : null;
    activeTarget.value = _open ? match?.targetKey : null;
    notifyListeners();
    if (reveal && match != null) _viewport?.reveal(match);
  }

  @override
  void dispose() {
    activeTarget.dispose();
    super.dispose();
  }
}

/// Lends a chat's [AgentChatFindController] to its timeline and rows.
class const AgentChatFindScope({
  super.key,
  required final AgentChatFindController controller,
  required super.child,
}) extends InheritedWidget {
  static AgentChatFindController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AgentChatFindScope>()
      ?.controller;

  @override
  bool updateShouldNotify(AgentChatFindScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// A timeline row find can land on. It outlines itself while it holds the
/// active match and tells find where it is, so a match can be scrolled into
/// view. Outside an [AgentChatFindScope] it is just [child].
class const AgentChatFindTarget({
  super.key,
  required final String targetKey,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<AgentChatFindTarget> createState() => _AgentChatFindTargetState();
}

class _AgentChatFindTargetState extends State<AgentChatFindTarget> {
  static const BoxDecoration _active = BoxDecoration(
    color: AleraTokens.accentSubtle,
    border: Border.fromBorderSide(BorderSide(color: AleraTokens.accent)),
    borderRadius: BorderRadius.all(Radius.circular(AleraTokens.radiusLg)),
  );

  AgentChatFindController? _find;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final find = AgentChatFindScope.maybeOf(context);
    if (identical(find, _find)) return;
    _find?.unregisterTarget(widget.targetKey, context);
    _find = find?..registerTarget(widget.targetKey, context);
  }

  @override
  void didUpdateWidget(covariant AgentChatFindTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey == widget.targetKey) return;
    _find
      ?..unregisterTarget(oldWidget.targetKey, context)
      ..registerTarget(widget.targetKey, context);
  }

  @override
  void dispose() {
    _find?.unregisterTarget(widget.targetKey, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final find = _find;
    if (find == null) return widget.child;
    // The decoration is always there, empty when inactive, so highlighting a
    // row never changes its subtree and loses no state below it.
    return ValueListenableBuilder<String?>(
      valueListenable: find.activeTarget,
      child: widget.child,
      builder: (context, active, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: active == widget.targetKey
            ? _active
            : const BoxDecoration(),
        child: child,
      ),
    );
  }
}
