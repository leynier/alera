import 'package:flutter/widgets.dart';

/// Keyboard-focus handles for the workbench surfaces, keyed by the id the
/// keyboard dispatcher already reasons about: a panel key (`tab:<id>` or a
/// tool key).
///
/// Surfaces register the [FocusScopeNode] that encloses their content, so a
/// shortcut can move focus into a pane without knowing what kind of tab it
/// shows: requesting focus on the scope lands on the surface's most recently
/// focused descendant (the terminal, the editor) and falls back to the scope
/// itself, whose focus change promotes the pane to the active group.
class WorkbenchPaneFocusRegistry {
  final Map<String, FocusScopeNode> _nodes = <String, FocusScopeNode>{};

  void register(String key, FocusScopeNode node) {
    _nodes[key] = node;
  }

  /// Drops [key] only while it still points at [node], so a surface remounted
  /// under the same key during the same frame is not unregistered by the
  /// outgoing element.
  void unregister(String key, FocusScopeNode node) {
    if (_nodes[key] == node) {
      _nodes.remove(key);
    }
  }

  bool isRegistered(String key) => _nodes.containsKey(key);

  /// Whether the primary focus is inside the surface registered under [key].
  bool hasFocus(String key) => _nodes[key]?.hasFocus ?? false;

  /// The first of [keys] whose surface contains the primary focus.
  String? focusedKeyAmong(Iterable<String> keys) {
    for (final key in keys) {
      if (hasFocus(key)) {
        return key;
      }
    }
    return null;
  }

  /// Moves keyboard focus into the surface registered under [key]. Returns
  /// false when nothing is registered there.
  bool focus(String key) {
    final node = _nodes[key];
    if (node == null) {
      return false;
    }
    node.requestFocus();
    return true;
  }
}

/// Whether the primary focus sits on a scope rather than on a widget, which is
/// where Flutter parks it when the focused content unmounts or when a pane is
/// focused with no history. A surface whose pane just became active may claim
/// the keyboard in that state; it must not take it from a field being typed in.
bool workbenchFocusIsParked() {
  final primary = FocusManager.instance.primaryFocus;
  return primary == null || primary is FocusScopeNode;
}

/// A [FocusScope] that publishes its node to a [WorkbenchPaneFocusRegistry]
/// under [registryKey] for as long as it is mounted.
class const WorkbenchRegisteredFocusScope({
  super.key,
  required final String registryKey,
  required final WorkbenchPaneFocusRegistry? registry,
  required final String debugLabel,
  final ValueChanged<bool>? onFocusChange,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<WorkbenchRegisteredFocusScope> createState() =>
      _WorkbenchRegisteredFocusScopeState();
}

class _WorkbenchRegisteredFocusScopeState
    extends State<WorkbenchRegisteredFocusScope> {
  late final FocusScopeNode _node = FocusScopeNode(
    debugLabel: widget.debugLabel,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    widget.registry?.register(widget.registryKey, _node);
  }

  @override
  void didUpdateWidget(covariant WorkbenchRegisteredFocusScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry ||
        oldWidget.registryKey != widget.registryKey) {
      oldWidget.registry?.unregister(oldWidget.registryKey, _node);
      widget.registry?.register(widget.registryKey, _node);
    }
  }

  @override
  void dispose() {
    widget.registry?.unregister(widget.registryKey, _node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _node,
      onFocusChange: widget.onFocusChange,
      child: widget.child,
    );
  }
}
