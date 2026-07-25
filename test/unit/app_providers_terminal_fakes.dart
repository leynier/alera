part of 'app_providers_test.dart';

class _FakeTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _events =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _events.stream;

  void emitExit(TerminalRuntimeExitEvent event) {
    _events.add(event);
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
  }

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {
    _events.close();
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    throw UnimplementedError();
  }

  @override
  TerminalSessionHandle? peekSession(String tabId) => null;

  @override
  void setActiveWorkspace(String? workspaceId) {}
}

class _FocusableTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _events =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> focusedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _events.stream;

  @override
  void closeTab(String tabId) {}

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {
    _events.close();
  }

  @override
  TerminalSessionHandle? peekSession(String tabId) => null;

  @override
  void setActiveWorkspace(String? workspaceId) {}

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _FocusableTerminalSessionHandle(
      workspace: workspace,
      tab: tab,
      onFocus: () => focusedTabIds.add(tab.id),
    );
  }
}

class _FocusableTerminalSessionHandle extends TerminalSessionHandle {
  _FocusableTerminalSessionHandle({
    required this.workspace,
    required this.tab,
    required this.onFocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final VoidCallback onFocus;

  @override
  String get displayTitle => tab.title;

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  String? get errorMessage => null;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox(key: key);
  }

  @override
  Future<void> ensureStarted() async {}

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  void requestFocus() {
    onFocus();
  }

  @override
  Future<void> restart() async {}
}
