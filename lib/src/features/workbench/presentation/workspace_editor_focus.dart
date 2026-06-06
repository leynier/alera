part of 'workspace_editor_surface.dart';

@visibleForTesting
int normalizeWorkspaceEditorTabSize(int tabSize) => tabSize.clamp(1, 8).toInt();

@visibleForTesting
class WorkspaceEditorFocusNode extends FocusNode {
  final Map<VoidCallback, List<VoidCallback>> _listenerWrappers =
      <VoidCallback, List<VoidCallback>>{};
  bool _suppressThirdPartyListeners = false;

  void suppressThirdPartyListeners() {
    _suppressThirdPartyListeners = true;
  }

  @override
  void addListener(VoidCallback listener) {
    // CodeForge registers an anonymous FocusNode listener that reads context
    // after unmount. Wrapping listeners lets this integration silence those
    // callbacks during disposal without forking the package.
    void wrapper() {
      if (_suppressThirdPartyListeners) {
        return;
      }
      listener();
    }

    (_listenerWrappers[listener] ??= <VoidCallback>[]).add(wrapper);
    super.addListener(wrapper);
  }

  @override
  void removeListener(VoidCallback listener) {
    final wrappers = _listenerWrappers[listener];
    final wrapper = wrappers == null || wrappers.isEmpty
        ? null
        : wrappers.removeLast();
    if (wrappers != null && wrappers.isEmpty) {
      _listenerWrappers.remove(listener);
    }
    super.removeListener(wrapper ?? listener);
  }
}
